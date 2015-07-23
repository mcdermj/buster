//
//  DMYAudioHandler.m
//
//  Copyright (c) 2015 - Jeremy C. McDermond (NH6Z)

// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

#import "DMYAudioHandler.h"

#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>

#import "TPCircularBuffer.h"
#import "TPCircularBuffer+AudioBufferList.h"
#import "DMYGatewayHandler.h"

static const AudioComponentDescription componentDescription = {
    .componentType = kAudioUnitType_Output,
    .componentSubType = kAudioUnitSubType_HALOutput,
    .componentManufacturer = kAudioUnitManufacturer_Apple,
    .componentFlags = 0,
    .componentFlagsMask = 0
};

static const AudioStreamBasicDescription outputFormat  = {
    .mSampleRate = 8000.0,
    .mFormatID = kAudioFormatLinearPCM,
    .mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger,
    .mBytesPerPacket = sizeof(int16_t),
    .mBytesPerFrame = sizeof(int16_t),
    .mFramesPerPacket = 1,
    .mChannelsPerFrame = 1,
    .mBitsPerChannel = sizeof(int16_t) * 8
};

static BOOL receiving = NO;

@interface DMYAudioHandler () {
    TPCircularBuffer playbackBuffer;
    TPCircularBuffer recordBuffer;
    AudioUnit outputUnit;
    AudioUnit inputUnit;
    AudioStreamBasicDescription inputFormat;
    dispatch_source_t inputAudioSource;
}

@property (readonly) AudioUnit inputUnit;
@property (readonly) TPCircularBuffer *recordBuffer;
@property (readonly) AudioStreamBasicDescription *inputFormat;

+(NSArray *)enumerateDevices:(AudioObjectPropertyScope)scope;
@end

static OSStatus playbackThreadCallback (void *userData, AudioUnitRenderActionFlags *actionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    int32_t availableBytes;
    void *bufferTail;
    TPCircularBuffer *buffer = (TPCircularBuffer *) userData;
    
    for(unsigned int i = 0; i < ioData->mNumberBuffers; ++i) {
        bufferTail = TPCircularBufferTail(buffer, &availableBytes);
        if((UInt32) availableBytes < ioData->mBuffers[i].mDataByteSize) {
            memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
            if(!receiving && availableBytes > 0) {
                memcpy(ioData->mBuffers[i].mData, bufferTail, availableBytes);
                TPCircularBufferConsume(buffer, availableBytes);
            }
        } else {
            memcpy(ioData->mBuffers[i].mData, bufferTail, ioData->mBuffers[i].mDataByteSize);
            TPCircularBufferConsume(buffer, ioData->mBuffers[i].mDataByteSize);
        }
    }
    
    return noErr;
}

static OSStatus recordThreadCallback (void *userData, AudioUnitRenderActionFlags *actionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    DMYAudioHandler *audioHandler = (__bridge DMYAudioHandler *) userData;
    
    OSStatus error;
    
    // NSLog(@"IN recordThreadCallback");
    
    AudioBufferList *bufferList = TPCircularBufferPrepareEmptyAudioBufferListWithAudioFormat(audioHandler.recordBuffer, audioHandler.inputFormat, inNumberFrames, inTimeStamp);
    if(!bufferList) {
        NSLog(@"recordBuffer is full\n");
        return kIOReturnSuccess;
    }
    
    error = AudioUnitRender(audioHandler.inputUnit, actionFlags, inTimeStamp, inBusNumber, inNumberFrames, bufferList);
    if(error != noErr) {
        NSLog(@"Error rendering input audio %d\n", error);
    }
    
    if(audioHandler.xmit)
        TPCircularBufferProduceAudioBufferList(audioHandler.recordBuffer, inTimeStamp);
    
    return kIOReturnSuccess;
}


@implementation DMYAudioHandler

@synthesize vocoder;
@synthesize xmit;

- (id) init {
    self = [super init];
    
    if(self) {
        TPCircularBufferInit(&playbackBuffer, 16384);
        TPCircularBufferInit(&recordBuffer, 16384);
        
        xmit = NO;
    }
    
    return self;
}

- (AudioUnit) inputUnit {
    return inputUnit;
}

- (TPCircularBuffer *) recordBuffer {
    return &recordBuffer;
}

- (AudioStreamBasicDescription *) inputFormat {
    return &inputFormat;
}

- (void) setXmit:(BOOL)_xmit {
    xmit = _xmit;
    
    if(xmit)
        dispatch_resume(inputAudioSource);
}

- (BOOL) xmit {
    return xmit;
}

-(void) queueAudioData:(void *)audioData withLength:(uint32)length {
    if(TPCircularBufferProduceBytes(&playbackBuffer, audioData, length) == false) {
        NSLog(@"No space left in buffer\n");
    }
    
}

- (BOOL) start {
    OSStatus error;
    AudioComponent outputComponent;
    
    
    //  Set up the speaker output audio
    CFRunLoopRef runLoop = NULL;
    AudioObjectPropertyAddress theAddress = { kAudioHardwarePropertyRunLoop, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
    error = AudioObjectSetPropertyData(kAudioObjectSystemObject, &theAddress, 0, NULL, sizeof(CFRunLoopRef), &runLoop);
    if(error != noErr) {
        NSLog(@"Couldn't set run loop\n");
    }
    
    outputComponent = AudioComponentFindNext(NULL, &componentDescription);
    error = AudioComponentInstanceNew(outputComponent, &outputUnit);
    if(error != noErr) {
        NSLog(@"Couldn't get the default output unit\n");
        return NO;
    }

    error = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outputFormat, sizeof(outputFormat));
    if(error != noErr) {
        NSLog(@"Couldn't set stream format for output unit\n");
        return NO;
    }
    
    AURenderCallbackStruct renderCallback;
    renderCallback.inputProc = playbackThreadCallback;
    renderCallback.inputProcRefCon = &playbackBuffer;
    error = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &renderCallback, sizeof(renderCallback));
    if(error != noErr) {
        NSLog(@"Couldn't set render callback\n");
        return NO;
    }
    
    error = AudioUnitInitialize(outputUnit);
    if(error != noErr) {
        NSLog(@"Couldn't initialize output unit\n");
        return NO;
    }

    error = AudioOutputUnitStart(outputUnit);
    if(error != noErr) {
        NSLog(@"Couldn't start output unit\n");
        return NO;
    }
    
    NSLog(@"Audio system set up\n");
    
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYNetworkStreamStart
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification) {
                                                      receiving = YES;
                                                      TPCircularBufferClear(&playbackBuffer);
                                                  }
     ];
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYNetworkStreamEnd
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification) {
                                                      receiving = NO;
                                                  }
     ];
    
    //  Set up microphone input audio
    error = AudioComponentInstanceNew(outputComponent, &inputUnit);
    if(error != noErr) {
        NSLog(@"Couldn't get the default output unit\n");
        return NO;
    }

    UInt32 enable = 1;
    error = AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, sizeof(enable));
    if(error != noErr) {
        NSLog(@"Couldn't enable output IO for input unit\n");
        return NO;
    }
    
    enable = 0;
    error = AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable, sizeof(enable));
    if(error != noErr) {
        NSLog(@"Couldn't enable output IO for input unit\n");
        return NO;
    }
    
     AudioDeviceID defaultDevice;
     UInt32 defaultDeviceSize = sizeof(defaultDevice);
     
    AudioObjectPropertyAddress defaultDeviceAddress = { kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
    error = AudioObjectGetPropertyData(defaultDevice, &defaultDeviceAddress, 0, NULL, &defaultDeviceSize, &defaultDevice);
    if(error != kAudioHardwareNoError) {
        NSLog(@"AudioObjectGetPropertyData (kAudioDevicePropertyDeviceNameCFString) failed\n");
        return NO;
    }
    
    error = AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &defaultDevice, sizeof(AudioDeviceID));
    if(error != noErr) {
        NSLog(@"Couldn't set input device: %ld\n", (long int) error);
        return NO;
    }
    
    defaultDeviceAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
    AudioValueRange hardwareSampleRate = {
        .mMinimum = 8000.0,
        .mMaximum = 8000.0
    };
    error = AudioObjectSetPropertyData(defaultDevice, &defaultDeviceAddress, 0, NULL, sizeof(hardwareSampleRate), &hardwareSampleRate);
    if(error != noErr) {
        NSLog(@"Couldn't set hardware sample rate\n");
        return NO;
    }

    UInt32 inputFormatSize = sizeof(inputFormat);
    error = AudioUnitGetProperty(inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &inputFormat, &inputFormatSize);
    if(error != noErr) {
        NSLog(@"Couldn't get stream output format for input unit\n");
        return NO;
    }
    
    inputFormat.mSampleRate = 8000.0;  //  This isn't going to be good for a AudioConverter
    inputFormat.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger| kAudioFormatFlagIsBigEndian;
    inputFormat.mBytesPerPacket = sizeof(int16_t);
    inputFormat.mBytesPerFrame = sizeof(int16_t);
    inputFormat.mFramesPerPacket = 1;
    inputFormat.mChannelsPerFrame = 1;
    inputFormat.mBitsPerChannel = sizeof(int16_t) * 8;
    
    error = AudioUnitSetProperty(inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &inputFormat, sizeof(inputFormat));
    if(error != noErr) {
        NSLog(@"Couldn't set stream format for input unit\n");
        return NO;
    }
    
    renderCallback.inputProc = recordThreadCallback;
    renderCallback.inputProcRefCon = (__bridge void *)(self);
    error = AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &renderCallback, sizeof(renderCallback));
    if(error != noErr) {
        NSLog(@"Couldn't set record render callback\n");
        return NO;
    }

    int allocBuffer = false;
    error = AudioUnitSetProperty(inputUnit, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Output, 1, &allocBuffer, sizeof(allocBuffer));
    if(error != noErr) {
        NSLog(@"Couldn't set buffer allocation\n");
        return NO;
    }

    error = AudioUnitInitialize(inputUnit);
    if(error != noErr) {
        NSLog(@"Couldn't initialize output unit\n");
        return NO;
    }
    
    error = AudioOutputUnitStart(inputUnit);
    if(error != noErr) {
        NSLog(@"Couldn't start output unit\n");
        return NO;
    }
    
    //  Set up a timer source to pull audio through the system and submit it to the vocoder.
    //  XXX this probably wants its own high priority serial queue to make sure we don't run more than one at once.
    inputAudioSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    dispatch_source_set_timer(inputAudioSource, dispatch_time(DISPATCH_TIME_NOW, 0), 20ull * NSEC_PER_MSEC, 1ull * NSEC_PER_MSEC);
    
    dispatch_source_set_event_handler(inputAudioSource, ^{
        // XXX We probably want to malloc the buffer list once and use it repeatedly.
        AudioBufferList bufferList;
        AudioTimeStamp timestamp;
        UInt32 numSamples = 160;
        BOOL last = NO;
        
        bufferList.mNumberBuffers = 1;
        bufferList.mBuffers[0].mNumberChannels = 1;
        bufferList.mBuffers[0].mDataByteSize = numSamples * sizeof(short);
        bufferList.mBuffers[0].mData = calloc(1, bufferList.mBuffers[0].mDataByteSize);
        
        TPCircularBufferDequeueBufferListFrames(&recordBuffer, &numSamples, &bufferList, &timestamp, &inputFormat);
        if(!xmit && numSamples == 0) {
            last = YES;
            dispatch_suspend(inputAudioSource);
        }
        
        [vocoder encodeData:bufferList.mBuffers[0].mData lastPacket:last];
        
        // NSLog(@"Got %u samples from buffer\n", numSamples);
        return;
    });
    
    // dispatch_resume(inputAudioSource);
    return YES;
}

+(NSArray *)enumerateInputDevices {
    return [self enumerateDevices:kAudioObjectPropertyScopeInput];
}

+(NSArray *)enumerateOutputDevices {
    return [self enumerateDevices:kAudioObjectPropertyScopeOutput];
}

+(void)enumerateDevicesWithBlock:(void(^)(AudioDeviceID))enumeratorBlock {
    OSStatus status;
    
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMaster
    };
    
    UInt32 dataSize = 0;
    status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize);
    if(status != kAudioHardwareNoError) {
        NSLog(@"AudioObjectGetPropertyDataSize (kAudioHardwarePropertyDevices) failed");
        return;
    }
    
    UInt32 deviceCount = (UInt32)(dataSize / sizeof(AudioDeviceID));
    AudioDeviceID *audioDevices = (AudioDeviceID *) malloc(dataSize);
    if(audioDevices == NULL) {
        NSLog(@"Unable to allocate memory");
        return;
    }
    
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize, audioDevices);
    if(status != kAudioHardwareNoError) {
        NSLog(@"AudioObjectGetPropertyData (kAudioHardwarePropertyDevices) failed");
        return;
    }
    
    for(UInt32 i = 0; i < deviceCount; ++i) {
        enumeratorBlock(audioDevices[i]);
    }
    
    free(audioDevices);
}

+(NSArray *)enumerateDevices:(AudioObjectPropertyScope)scope {

    NSMutableArray *devices = [NSMutableArray arrayWithCapacity:1];
    
    NSParameterAssert(scope == kAudioObjectPropertyScopeOutput ||
                      scope == kAudioObjectPropertyScopeInput);
    
    [DMYAudioHandler enumerateDevicesWithBlock:^(AudioDeviceID deviceId){
        NSString *deviceName;
        NSString *deviceUID;
        OSStatus status;
        
        UInt32 dataSize = sizeof(deviceName);
        AudioObjectPropertyAddress propertyAddress = {
            kAudioDevicePropertyDeviceNameCFString,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMaster
        };

        status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, NULL, &dataSize, &deviceName);
        if(status != kAudioHardwareNoError) {
            NSLog(@"AudioObjectGetPropertyData (kAudioDevicePropertyDeviceNameCFString) failed");
            return;
        }
        
        dataSize = sizeof(deviceUID);
        propertyAddress.mSelector = kAudioDevicePropertyDeviceUID;
        status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, NULL, &dataSize, &deviceUID);
        if(status != kAudioHardwareNoError) {
            NSLog(@"AudioObjectGetPropertyData (kAudioDevicePropertyDeviceNameCFString) failed");
            return;
        }
    
        //  We have to see if there are any audio buffers for the appropriate scope to see if the device supports
        //  that scope.
        propertyAddress.mScope = scope;
        dataSize = 0;
        propertyAddress.mSelector = kAudioDevicePropertyStreamConfiguration;
        status = AudioObjectGetPropertyDataSize(deviceId, &propertyAddress, 0, NULL, &dataSize);
        if(status != kAudioHardwareNoError) {
            NSLog(@"AudioObjectGetPropertyDataSize (kAudioDevicePropertyStreamConfiguration) failed");
            return;
        }
    
        AudioBufferList *bufferList = (AudioBufferList *) malloc(dataSize);
        if(bufferList == NULL) {
            NSLog(@"Unable to malloc memory");
            return;
        }
    
        status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, NULL, &dataSize, bufferList);
        if(status != kAudioHardwareNoError || bufferList->mNumberBuffers == 0) {
            if(status != kAudioHardwareNoError)
                NSLog(@"AudioObjectGetPropertyData (kAudioDevicePropertyStreamConfiguration) failed");
            free(bufferList);
            bufferList = NULL;
            return;
        }
    
        free(bufferList);
        bufferList = NULL;
    
        [devices addObject: @{ @"name":deviceName, @"uid":deviceUID, @"id":[NSNumber numberWithInt:deviceId] }];
    }];

    return [NSArray arrayWithArray:devices];
}


@end

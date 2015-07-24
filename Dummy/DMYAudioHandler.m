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

static inline BOOL CheckStatus(OSStatus error, const char *operation);

@interface DMYAudioHandler () {
    TPCircularBuffer playbackBuffer;
    TPCircularBuffer recordBuffer;
    AudioUnit outputUnit;
    AudioUnit inputUnit;
    AudioStreamBasicDescription inputFormat;
    dispatch_source_t inputAudioSource;
    AudioConverterRef inputConverter;
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

static OSStatus audioConverterCallback(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    DMYAudioHandler *audioHandler = (__bridge DMYAudioHandler *) inUserData;
    AudioTimeStamp timestamp;
    
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mNumberChannels = 1;
    ioData->mBuffers[0].mDataByteSize = *ioNumberDataPackets * sizeof(short);
    ioData->mBuffers[0].mData = calloc(1, ioData->mBuffers[0].mDataByteSize);
    
    //NSLog(@"Being called for %d samples", *ioNumberDataPackets);
    
    TPCircularBufferDequeueBufferListFrames(audioHandler.recordBuffer, ioNumberDataPackets, ioData, &timestamp, audioHandler.inputFormat);
    
    ioData->mBuffers[0].mDataByteSize = *ioNumberDataPackets * sizeof(short);
    if(*ioNumberDataPackets == 0)
        return kAudioConverterErr_UnspecifiedError;
    
    //NSLog(@"Got %d samples", *ioNumberDataPackets);
    //NSLog(@"Buffers are %d large", ioData->mBuffers[0].mDataByteSize);
    
    return noErr;
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

static inline BOOL CheckStatus(OSStatus error, const char *operation) {
    if(error == noErr)
        return YES;
    
    char str[20];
    // see if it appears to be a 4-char-code
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else {
        // no, format it as an integer
        sprintf(str, "%d", (int)error);
    }
    
    switch(error) {
        case kAudioUnitErr_InvalidProperty:
            NSLog(@"Error: %s (%s) kAudioUnitErr_InvalidProperty", operation, str);
            break;
            
        case kAudioUnitErr_InvalidParameter:
            NSLog(@"Error: %s (%s) kAudioUnitErr_InvalidParameter", operation, str);
            break;
            
        case kAudioUnitErr_InvalidElement:
            NSLog(@"Error: %s (%s) kAudioUnitErr_InvalidElement", operation, str);
            break;
            
        case kAudioUnitErr_NoConnection:
            NSLog(@"Error: %s (%s) kAudioUnitErr_NoConnection", operation, str);
            break;
            
        case kAudioUnitErr_FailedInitialization:
            NSLog(@"Error: %s (%s) kAudioUnitErr_FailedInitialization", operation, str);
            break;
            
        case kAudioUnitErr_TooManyFramesToProcess:
            NSLog(@"Error: %s (%s) kAudioUnitErr_TooManyFramesToProcess", operation, str);
            break;
            
        case kAudioUnitErr_InvalidFile:
            NSLog(@"Error: %s (%s) kAudioUnitErr_InvalidFile", operation, str);
            break;
            
        case kAudioUnitErr_FormatNotSupported:
            NSLog(@"Error: %s (%s) kAudioUnitErr_FormatNotSupported", operation, str);
            break;
            
        case kAudioUnitErr_Uninitialized:
            NSLog(@"Error: %s (%s) kAudioUnitErr_Uninitialized", operation, str);
            break;
            
        case kAudioUnitErr_InvalidScope:
            NSLog(@"Error: %s (%s) kAudioUnitErr_InvalidScope", operation, str);
            break;
            
        case kAudioUnitErr_PropertyNotWritable:
            NSLog(@"Error: %s (%s) kAudioUnitErr_PropertyNotWritable", operation, str);
            break;
            
        case kAudioUnitErr_InvalidPropertyValue:
            NSLog(@"Error: %s (%s) kAudioUnitErr_InvalidPropertyValue", operation, str);
            break;
            
        case kAudioUnitErr_PropertyNotInUse:
            NSLog(@"Error: %s (%s) kAudioUnitErr_PropertyNotInUse", operation, str);
            break;
            
        case kAudioUnitErr_Initialized:
            NSLog(@"Error: %s (%s) kAudioUnitErr_Initialized", operation, str);
            break;
            
        case kAudioUnitErr_InvalidOfflineRender:
            NSLog(@"Error: %s (%s) kAudioUnitErr_InvalidOfflineRender", operation, str);
            break;
            
        case kAudioUnitErr_Unauthorized:
            NSLog(@"Error: %s (%s) kAudioUnitErr_Unauthorized", operation, str);
            break;
        default:
            NSLog(@"Error: %s (%s)", operation, str);
            break;
    }

    return NO;
}

- (BOOL) start {
    AudioComponent outputComponent;
    
    //  Set up the CoreAudio run loop and find the Output HAL
    CFRunLoopRef runLoop = NULL;
    AudioObjectPropertyAddress theAddress = { kAudioHardwarePropertyRunLoop, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
    CheckStatus(AudioObjectSetPropertyData(kAudioObjectSystemObject, &theAddress, 0, NULL, sizeof(CFRunLoopRef), &runLoop), "AudioObjectSetPropertyData(kAudioHardwarePropertyRunLoop");
    
    outputComponent = AudioComponentFindNext(NULL, &componentDescription);
    
    //  Set up the output unit for speaker output
    if(!CheckStatus(AudioComponentInstanceNew(outputComponent, &outputUnit), "AudioComponentInstanceNew"))
        return NO;
    
    if(!CheckStatus(AudioUnitSetProperty(outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outputFormat, sizeof(outputFormat)), "AudioUnitSetProperty(kAudioUnitPropertyStreamFormat)"))
        return NO;
    
    AURenderCallbackStruct renderCallback;
    renderCallback.inputProc = playbackThreadCallback;
    renderCallback.inputProcRefCon = &playbackBuffer;
    
    if(!CheckStatus(AudioUnitSetProperty(outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &renderCallback, sizeof(renderCallback)), "AudioUnitSetProperty(kAudioUnitProperty_SetRenderCallback)"))
        return NO;
    
    if(!CheckStatus(AudioUnitInitialize(outputUnit), "AudioUnitInitialize"))
        return NO;
    
    if(!CheckStatus(AudioOutputUnitStart(outputUnit), "AudioOutputUnitStart"))
        return NO;
    
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
    if(!CheckStatus(AudioComponentInstanceNew(outputComponent, &inputUnit), "AudioComponentInstanceNew"))
        return NO;
    
    UInt32 enable = 1;
    if(!CheckStatus(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, sizeof(enable)), "AudioUnitSetProperty(kAudioOutputUnitProperty_EnableIO"))
        return NO;
    
    enable = 0;
    if(!CheckStatus(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable, sizeof(enable)), "AudioUnitSetProperty(kAudioOutputUnitProperty_EnableIO"))
        return NO;
    
    AudioDeviceID defaultDevice;
    UInt32 defaultDeviceSize = sizeof(defaultDevice);
    AudioObjectPropertyAddress defaultDeviceAddress = { kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
    
    if(!CheckStatus(AudioObjectGetPropertyData(kAudioObjectSystemObject, &defaultDeviceAddress, 0, NULL, &defaultDeviceSize, &defaultDevice), "AudioUnitGetPropertyData(kAudioHardwarePropertyDefaultInputDevice)"))
        return NO;
    
    if(!CheckStatus(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &defaultDevice, sizeof(AudioDeviceID)), "AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)"))
        return NO;
    
    renderCallback.inputProc = recordThreadCallback;
    renderCallback.inputProcRefCon = (__bridge void *)(self);
    if(!CheckStatus(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &renderCallback, sizeof(renderCallback)), "AudioUnitSetProperty(kAudioOutputUnitProperty_SetInputCallback)"))
        return NO;
    
    int allocBuffer = false;
    if(!CheckStatus(AudioUnitSetProperty(inputUnit, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Output, 1, &allocBuffer, sizeof(allocBuffer)), "AudioUnitSetProperty(kAudioUnitProperty_ShouldAllocateBuffer)"))
        return NO;
    
    //  Need to get the possible hardware rates here to see if we support 8k.  If we don't, we're going to have to resample.
    //  If we have to resample, we'd prefer to set the hardware sample rate to 48k if possible because it will make the
    //  resampling rate integral rather than fractional.
    
    defaultDeviceAddress.mSelector = kAudioDevicePropertyAvailableNominalSampleRates;
    UInt32 sampleRatesSize = 0;
    if(!CheckStatus(AudioObjectGetPropertyDataSize(defaultDevice, &defaultDeviceAddress, 0, NULL, &sampleRatesSize), "AudioObjectGetPropertyDataSize(kAudioDevicePropertyAvailableNominalSampleRates"))
        return NO;
    
    AudioValueRange *sampleRateRanges = (AudioValueRange *) malloc(sampleRatesSize);
    
    if(!CheckStatus(AudioObjectGetPropertyData(defaultDevice, &defaultDeviceAddress, 0, NULL, &sampleRatesSize, sampleRateRanges), "AudioObjectGetPropertyData(kAudioDevicePropertyAvailableNominalSampleRates"))
        return NO;
    
    double hardwareSampleRate = 0.0;
    for(int i = 0; i < sampleRatesSize / sizeof(AudioValueRange); ++i) {
        NSLog(@"Range %d: Max = %f, Min = %f", i, sampleRateRanges[i].mMaximum, sampleRateRanges[i].mMinimum);
        if(sampleRateRanges[i].mMaximum >= 8000.0 && sampleRateRanges[i].mMinimum <= 8000.0)
            hardwareSampleRate = 8000.0;
        if(sampleRateRanges[i].mMinimum >= 48000.0 && sampleRateRanges[i].mMinimum <= 48000.0 && hardwareSampleRate != 8000.0)
            hardwareSampleRate = 48000.0;
    }
    
    NSLog(@"We want hardware sample rate to be %f\n", hardwareSampleRate);
    if(hardwareSampleRate != 0.0) {
        defaultDeviceAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
        AudioValueRange hardwareSampleRateRange = {
            .mMinimum = hardwareSampleRate,
            .mMaximum = hardwareSampleRate
        };
        if(!CheckStatus(AudioObjectSetPropertyData(defaultDevice, &defaultDeviceAddress, 0, NULL, sizeof(hardwareSampleRateRange), &hardwareSampleRateRange), "AudioObjectSetPropertyData(kAudioDevicePropertyNominalSampleRate)"))
            return NO;
    } else {
        AudioValueRange hardwareSampleRateRange;
        UInt32 rangeSize = sizeof(hardwareSampleRateRange);
        defaultDeviceAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
        if(!CheckStatus(AudioObjectGetPropertyData(defaultDevice, &defaultDeviceAddress, 0, NULL, &rangeSize, &hardwareSampleRateRange), "AudioObjectGetPropertyData(kAudioDevicePropertyNominalSampleRate"))
            return NO;
        
        hardwareSampleRate = hardwareSampleRateRange.mMinimum;
    }
    NSLog(@"We got hardware sample rate to be %f\n", hardwareSampleRate);
    
    UInt32 inputFormatSize = sizeof(inputFormat);
    if(!CheckStatus(AudioUnitGetProperty(inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &inputFormat, &inputFormatSize), "AudioUnitGetProperty(kAudioUnitProperty_StreamFormat)"))
        return NO;
    
    inputFormat.mSampleRate = hardwareSampleRate;
    inputFormat.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger| kAudioFormatFlagIsBigEndian;
    inputFormat.mBytesPerPacket = sizeof(int16_t);
    inputFormat.mBytesPerFrame = sizeof(int16_t);
    inputFormat.mFramesPerPacket = 1;
    inputFormat.mChannelsPerFrame = 1;
    inputFormat.mBitsPerChannel = sizeof(int16_t) * 8;
    
    if(!CheckStatus(AudioUnitSetProperty(inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &inputFormat, sizeof(inputFormat)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)"))
        return NO;
    
    //  Set up a timer source to pull audio through the system and submit it to the vocoder.
    //  XXX this probably wants its own high priority serial queue to make sure we don't run more than one at once.
    inputAudioSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    dispatch_source_set_timer(inputAudioSource, dispatch_time(DISPATCH_TIME_NOW, 0), 20ull * NSEC_PER_MSEC, 1ull * NSEC_PER_MSEC);
    
    if(hardwareSampleRate == 8000.0) {
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
    } else {
        AudioConverterNew(&inputFormat, &outputFormat, &inputConverter);
        
        dispatch_source_set_event_handler(inputAudioSource, ^{
            UInt32 numSamples = 160;
            AudioBufferList bufferList;
            BOOL last = NO;
            
            bufferList.mNumberBuffers = 1;
            bufferList.mBuffers[0].mNumberChannels = 1;
            bufferList.mBuffers[0].mDataByteSize = numSamples * sizeof(short);
            bufferList.mBuffers[0].mData = calloc(1, bufferList.mBuffers[0].mDataByteSize);
            
            OSStatus status = AudioConverterFillComplexBuffer(inputConverter, audioConverterCallback, (__bridge void *)(self), &numSamples, &bufferList, NULL);
            
            if(status != noErr && status != kAudioConverterErr_UnspecifiedError)
                return;
            
            // NSLog(@"Got %d samples from the AudioConverter", numSamples);
            
            if(!xmit && numSamples == 0) {
                last = YES;
                dispatch_suspend(inputAudioSource);
            }
            
            [vocoder encodeData:bufferList.mBuffers[0].mData lastPacket:last];            
           return;
        });
    }
    
    //  Start everything up.
    
    if(!CheckStatus(AudioUnitInitialize(inputUnit), "AudioUnitInitialize"))
        return NO;
    
    if(!CheckStatus(AudioOutputUnitStart(inputUnit), "AudioOutputUnitStart"))
        return NO;
    
    NSLog(@"Audio system set up\n");
    
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

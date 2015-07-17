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


@interface DMYAudioHandler () {
    TPCircularBuffer playbackBuffer;
    AudioUnit outputUnit;
}

@end

@implementation DMYAudioHandler

- (id) init {
    self = [super init];
    
    if(self) {
        TPCircularBufferInit(&playbackBuffer, 16384);
    }
    
    return self;
}

-(void) queueAudioData:(void *)audioData withLength:(uint32)length {
    if(TPCircularBufferProduceBytes(&playbackBuffer, audioData, length) == false) {
        NSLog(@"No space left in buffer\n");
    }
    
}

- (BOOL) start {
    OSStatus error;
    AudioComponent outputComponent;
    
    CFRunLoopRef runLoop = NULL;
    AudioObjectPropertyAddress theAddress = { kAudioHardwarePropertyRunLoop, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
    error = AudioObjectSetPropertyData(kAudioObjectSystemObject, &theAddress, 0, NULL, sizeof(CFRunLoopRef), &runLoop);
    if(error != noErr) {
        fprintf(stderr, "Couldn't set run loop\n");
    }
    
    outputComponent = AudioComponentFindNext(NULL, &componentDescription);
    error = AudioComponentInstanceNew(outputComponent, &outputUnit);
    if(error != noErr) {
        fprintf(stderr, "Couldn't get the default output unit\n");
        return false;
    }

    error = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outputFormat, sizeof(outputFormat));
    if(error != noErr) {
        fprintf(stderr, "Couldn't set stream format for output unit\n");
        return false;
    }
    
    AURenderCallbackStruct renderCallback;
    renderCallback.inputProc = playbackThreadCallback;
    renderCallback.inputProcRefCon = &playbackBuffer;
    error = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &renderCallback, sizeof(renderCallback));
    if(error != noErr) {
        fprintf(stderr, "Couldn't set render callback\n");
        return false;
    }
    
    error = AudioUnitInitialize(outputUnit);
    if(error != noErr) {
        fprintf(stderr, "Couldn't initialize output unit\n");
        return false;
    }

    error = AudioOutputUnitStart(outputUnit);
    if(error != noErr) {
        fprintf(stderr, "Couldn't start output unit\n");
        return false;
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

    return YES;
}


@end

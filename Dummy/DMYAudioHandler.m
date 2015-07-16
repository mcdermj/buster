//
//  DMYAudioHandler.m
//  Dummy
//
//  Created by Jeremy McDermond on 7/16/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "DMYAudioHandler.h"

#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>

#import "TPCircularBuffer.h"

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

static OSStatus playbackThreadCallback (void *userData, AudioUnitRenderActionFlags *actionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    int32_t availableBytes;
    void *bufferTail;
    TPCircularBuffer *buffer = (TPCircularBuffer *) userData;
    
    for(unsigned int i = 0; i < ioData->mNumberBuffers; ++i) {
        bufferTail = TPCircularBufferTail(buffer, &availableBytes);
        if((UInt32) availableBytes < ioData->mBuffers[i].mDataByteSize) {
            memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
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

    return YES;
}


@end

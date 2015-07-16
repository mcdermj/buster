//
//  AppDelegate.m
//  Dummy
//
//  Created by Jeremy McDermond on 7/10/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "AppDelegate.h"

#import "DMYGatewayHandler.h"
#import "DMYDV3KVocoder.h"
#import "DMYAudioHandler.h"

@interface AppDelegate () {
    DMYDV3KVocoder *vocoder;
    DMYAudioHandler *audio;
}

@end

@implementation AppDelegate

@synthesize network;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    network = [[DMYGatewayHandler alloc] initWithRemoteAddress:@"127.0.0.1" remotePort:20010 localPort:20011];
    vocoder = [[DMYDV3KVocoder alloc] initWithPort:@"/dev/cu.usbserial-DA016UVB"];
    audio = [[DMYAudioHandler alloc] init];
    
    
    network.xmitRepeater = @"NH6Z   B";
    network.xmitMyCall = @"NH6Z";
    
    network.vocoder = vocoder;
    vocoder.audio = audio;
    
    [audio start];
    [vocoder start];
    [network start];
    
    
    // [network linkTo:@"REF001 C"];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end

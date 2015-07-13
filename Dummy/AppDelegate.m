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

@interface AppDelegate () {
    DMYGatewayHandler *network;
    DMYDV3KVocoder *vocoder;
}

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    network = [[DMYGatewayHandler alloc] initWithRemoteAddress:@"127.0.0.1" remotePort:20010 localPort:20011];
    [network start];
    
    vocoder = [[DMYDV3KVocoder alloc] initWithPort:@"/dev/cu.usbserial-DA016UVB"];
    [vocoder start];
    
    network.vocoder = vocoder;
    
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end

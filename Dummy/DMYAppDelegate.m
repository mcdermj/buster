//
//  DMYAppDelegate.m
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

#import "DMYAppDelegate.h"

#import "DMYGatewayHandler.h"
#import "DMYDV3KVocoder.h"
#import "DMYAudioHandler.h"



@interface DMYAppDelegate () {
    // DMYAudioHandler *audio;
}

@end

@implementation DMYAppDelegate

@synthesize network;
@synthesize vocoder;
@synthesize audio;
@synthesize txKeyCode;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    NSURL *defaultPrefsFile = [[NSBundle mainBundle]
                               URLForResource:@"DefaultPreferences" withExtension:@"plist"];
    NSDictionary *defaultPrefs =
    [NSDictionary dictionaryWithContentsOfURL:defaultPrefsFile];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultPrefs];
    
    network = [[DMYGatewayHandler alloc] initWithRemoteAddress:[[NSUserDefaults standardUserDefaults] stringForKey:@"gatewayAddr"] remotePort:[[NSUserDefaults standardUserDefaults] integerForKey:@"gatewayPort"] localPort:[[NSUserDefaults standardUserDefaults] integerForKey:@"repeaterPort"]];
    
    NSString *portName = [[NSUserDefaults standardUserDefaults] stringForKey:@"dv3kSerialPort"];
    if(!portName) {
        NSArray *ports = [DMYDV3KVocoder ports];
        if(ports.count == 1)
            [[NSUserDefaults standardUserDefaults] setObject:ports[0] forKey:@"dv3kSerialPort"];
    }
    
    vocoder = [[DMYDV3KVocoder alloc] initWithPort:[[NSUserDefaults standardUserDefaults] stringForKey:@"dv3kSerialPort"]
                                          andSpeed:[[NSUserDefaults standardUserDefaults] integerForKey:@"dv3kSerialPortBaud"]];
    
    audio = [[DMYAudioHandler alloc] init];
    
    network.xmitRpt1Call = [[NSUserDefaults standardUserDefaults] stringForKey:@"rpt1Call"];
    network.xmitRpt1Call = [[NSUserDefaults standardUserDefaults] stringForKey:@"rpt2Call"];
    network.xmitMyCall = [[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"];
    [network bind:@"xmitMyCall" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.myCall" options:nil];
    [network bind:@"xmitRpt1Call" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.rpt1Call" options:nil];
    [network bind:@"xmitRpt2Call" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.rpt2Call" options:nil];
    [network bind:@"gatewayAddr" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.gatewayAddr" options:nil];
    [network bind:@"gatewayPort" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.gatewayPort" options:nil];
    [network bind:@"repeaterPort" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.repeaterPort" options:nil];
    [self bind:@"txKeyCode" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.shortcutValue" options:@{NSValueTransformerNameBindingOption: MASDictionaryTransformerName}];
    
    [vocoder bind:@"speed" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.dv3kSerialPortBaud" options:nil];
    [vocoder bind:@"serialPort" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.dv3kSerialPort" options:nil];
    
    network.vocoder = vocoder;
    audio.vocoder = vocoder;
    vocoder.audio = audio;
    
    NSString *inputUid = [[NSUserDefaults standardUserDefaults] stringForKey:@"inputAudioDevice"];
    if(!inputUid) {
        audio.inputDevice = audio.defaultInputDevice;
    } else {
        for(NSDictionary *entry in [DMYAudioHandler enumerateInputDevices])
            if([entry[@"uid"] isEqualToString:inputUid])
                audio.inputDevice = ((NSNumber *)entry[@"id"]).intValue;
     }
    
    NSString *outputUid = [[NSUserDefaults standardUserDefaults] stringForKey:@"outputAudioDevice"];
    if(!outputUid) {
        audio.outputDevice = audio.defaultOutputDevice;
    } else {
        for(NSDictionary *entry in [DMYAudioHandler enumerateOutputDevices])
            if([entry[@"uid"] isEqualToString:outputUid])
                audio.outputDevice = ((NSNumber *)entry[@"id"]).intValue;
    }
    
    
    /* [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyDownMask handler:^NSEvent *(NSEvent *event){
        NSLog(@"Got a keydown event: %@", event);
        return event;
    }]; */

    
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYVocoderDeviceChanged
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock: ^(NSNotification *notification) {
                                                        [[NSUserDefaults standardUserDefaults] setObject:vocoder.serialPort forKey:@"dv3kSerialPort"];
                                                  }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYAudioDeviceChanged
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock: ^(NSNotification *notification) {
                                                      for(NSDictionary *entry in [DMYAudioHandler enumerateInputDevices]) {
                                                          if(((NSNumber *)entry[@"id"]).intValue == audio.inputDevice) {
                                                              [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"inputAudioDevice"];
                                                          }
                                                      }
                                                      
                                                      for(NSDictionary *entry in [DMYAudioHandler enumerateOutputDevices]) {
                                                          if(((NSNumber *)entry[@"id"]).intValue == audio.outputDevice) {
                                                              [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"outputAudioDevice"];
                                                          }
                                                      }
                                                  }];


    
    [audio start];
    if(![vocoder start]){
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSWarningAlertStyle;
        alert.messageText = @"Cannot Open the Serial Port";
        alert.informativeText = @"Please check your serial port and speed settings in the Perferences menu";
        [alert runModal];
    };
    [network start];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

-(void)keyDown:(NSEvent *)theEvent {
    NSLog(@"Got an event %@", theEvent);
}

@end

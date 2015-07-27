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

#import "DMYDataEngine.h"



@interface DMYAppDelegate ()
@end

@implementation DMYAppDelegate

@synthesize txKeyCode;

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
    NSURL *defaultPrefsFile = [[NSBundle mainBundle]
                               URLForResource:@"DefaultPreferences" withExtension:@"plist"];
    NSDictionary *defaultPrefs =
    [NSDictionary dictionaryWithContentsOfURL:defaultPrefsFile];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultPrefs];
    
    DMYDataEngine *engine = [DMYDataEngine sharedInstance];
    
    [engine.network bind:@"xmitMyCall" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.myCall" options:nil];
    [engine.network bind:@"xmitRpt1Call" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.rpt1Call" options:nil];
    [engine.network bind:@"xmitRpt2Call" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.rpt2Call" options:nil];
    [engine.network bind:@"gatewayAddr" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.gatewayAddr" options:nil];
    [engine.network bind:@"gatewayPort" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.gatewayPort" options:nil];
    [engine.network bind:@"repeaterPort" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.repeaterPort" options:nil];
    
    [self bind:@"txKeyCode" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.shortcutValue" options:@{NSValueTransformerNameBindingOption: MASDictionaryTransformerName}];
    
    [engine.vocoder bind:@"speed" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.dv3kSerialPortBaud" options:nil];
    [engine.vocoder bind:@"serialPort" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.dv3kSerialPort" options:nil];
    
    
    NSString *portName = [[NSUserDefaults standardUserDefaults] stringForKey:@"dv3kSerialPort"];
    if(!portName) {
        NSArray *ports = [DMYDV3KVocoder ports];
        if(ports.count == 1)
            [[NSUserDefaults standardUserDefaults] setObject:ports[0] forKey:@"dv3kSerialPort"];
    }

    NSString *inputUid = [[NSUserDefaults standardUserDefaults] stringForKey:@"inputAudioDevice"];
    if(!inputUid) {
        engine.audio.inputDevice = engine.audio.defaultInputDevice;
    } else {
        for(NSDictionary *entry in [DMYAudioHandler enumerateInputDevices])
            if([entry[@"uid"] isEqualToString:inputUid])
                engine.audio.inputDevice = ((NSNumber *)entry[@"id"]).intValue;
     }
    
    NSString *outputUid = [[NSUserDefaults standardUserDefaults] stringForKey:@"outputAudioDevice"];
    if(!outputUid) {
        engine.audio.outputDevice = engine.audio.defaultOutputDevice;
    } else {
        for(NSDictionary *entry in [DMYAudioHandler enumerateOutputDevices])
            if([entry[@"uid"] isEqualToString:outputUid])
                engine.audio.outputDevice = ((NSNumber *)entry[@"id"]).intValue;
    }
    
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYVocoderDeviceChanged
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock: ^(NSNotification *notification) {
                                                        [[NSUserDefaults standardUserDefaults] setObject:engine.vocoder.serialPort forKey:@"dv3kSerialPort"];
                                                  }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYAudioDeviceChanged
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock: ^(NSNotification *notification) {
                                                      for(NSDictionary *entry in [DMYAudioHandler enumerateInputDevices]) {
                                                          if(((NSNumber *)entry[@"id"]).intValue == engine.audio.inputDevice) {
                                                              [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"inputAudioDevice"];
                                                          }
                                                      }
                                                      
                                                      for(NSDictionary *entry in [DMYAudioHandler enumerateOutputDevices]) {
                                                          if(((NSNumber *)entry[@"id"]).intValue == engine.audio.outputDevice) {
                                                              [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"outputAudioDevice"];
                                                          }
                                                      }
                                                  }];


    
    [engine.audio start];
    if(![engine.vocoder start]){
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSWarningAlertStyle;
        alert.messageText = @"Cannot Open the Serial Port";
        alert.informativeText = @"Please check your serial port and speed settings in the Perferences menu";
        [alert runModal];
    };
    [engine.network start];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end

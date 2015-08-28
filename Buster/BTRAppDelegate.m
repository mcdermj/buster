//
//  BTRAppDelegate.m
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

#import "BTRAppDelegate.h"

#import "BTRDataEngine.h"
#import "BTRDV3KSerialVocoder.h"
#import "MASDictionaryTransformer.h"
#import "BTRSlowDataCoder.h"
#import "BTRAudioHandler.h"

#import "BTRDPlusLink.h"

@interface BTRAppDelegate () 
@end

@implementation BTRAppDelegate

@synthesize txKeyCode;

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
    NSURL *defaultPrefsFile = [[NSBundle mainBundle]
                               URLForResource:@"DefaultPreferences" withExtension:@"plist"];
    NSDictionary *defaultPrefs =
    [NSDictionary dictionaryWithContentsOfURL:defaultPrefsFile];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultPrefs];

    BTRDataEngine *engine = [BTRDataEngine sharedInstance];
    [engine.slowData bind:@"message" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.slowDataMessage" options:nil];
    
        
    [self bind:@"txKeyCode" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.shortcutValue" options:@{NSValueTransformerNameBindingOption: MASDictionaryTransformerName}];
    
    NSString *inputUid = [[NSUserDefaults standardUserDefaults] stringForKey:@"inputAudioDevice"];
    if(!inputUid) {
        engine.audio.inputDevice = engine.audio.defaultInputDevice;
    } else {
        for(NSDictionary *entry in [BTRAudioHandler enumerateInputDevices])
            if([entry[@"uid"] isEqualToString:inputUid])
                engine.audio.inputDevice = ((NSNumber *)entry[@"id"]).intValue;
     }
    
    NSString *outputUid = [[NSUserDefaults standardUserDefaults] stringForKey:@"outputAudioDevice"];
    if(!outputUid) {
        engine.audio.outputDevice = engine.audio.defaultOutputDevice;
    } else {
        for(NSDictionary *entry in [BTRAudioHandler enumerateOutputDevices])
            if([entry[@"uid"] isEqualToString:outputUid])
                engine.audio.outputDevice = ((NSNumber *)entry[@"id"]).intValue;
    }
    
    [[NSNotificationCenter defaultCenter] addObserverForName: BTRAudioDeviceChanged
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock: ^(NSNotification *notification) {
                                                      for(NSDictionary *entry in [BTRAudioHandler enumerateInputDevices]) {
                                                          if(((NSNumber *)entry[@"id"]).intValue == engine.audio.inputDevice) {
                                                              [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"inputAudioDevice"];
                                                          }
                                                      }
                                                      
                                                      for(NSDictionary *entry in [BTRAudioHandler enumerateOutputDevices]) {
                                                          if(((NSNumber *)entry[@"id"]).intValue == engine.audio.outputDevice) {
                                                              [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"outputAudioDevice"];
                                                          }
                                                      }
                                                  }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [engine.audio start];
        if(![engine.vocoder start])
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [[NSAlert alloc] init];
                alert.alertStyle = NSWarningAlertStyle;
                alert.messageText = @"Cannot Open the Serial Port";
                alert.informativeText = @"Please check your serial port and speed settings in the Perferences menu";
                [alert runModal];
            });
    });    
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end

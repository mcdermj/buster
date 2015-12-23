/*
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at
 * https://solaris.java.net/license.html
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at
 * https://solaris.java.net/license.html.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
 * License for the specific language governing permissions and limitations under
 * the License.
 *
 * Copyright (c) 2015 Jeremy McDermond (NH6Z). All rights reserved.
 *
 */

#import "BTRAppDelegate.h"

#import <HockeySDK/HockeySDK.h>

#import "BTRDataEngine.h"
#import "BTRDV3KSerialVocoder.h"
#import "BTRSlowDataCoder.h"
#import "BTRAudioHandler.h"

@interface BTRAppDelegate () 
@end

@implementation BTRAppDelegate

-(void) awakeFromNib {
    NSURL *defaultPrefsFile = [[NSBundle mainBundle]
                               URLForResource:@"DefaultPreferences" withExtension:@"plist"];
    NSDictionary *defaultPrefs =
    [NSDictionary dictionaryWithContentsOfURL:defaultPrefsFile];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultPrefs];
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
    [[BITHockeyManager sharedHockeyManager] configureWithIdentifier:@"cc76112de7b80cf017acd344d6072ec9"];
    // Do some additional configuration if needed here
    [[BITHockeyManager sharedHockeyManager] startManager];

    BTRDataEngine *engine = [BTRDataEngine sharedInstance];
    [engine.slowData bind:@"message" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.slowDataMessage" options:nil];
    
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
        engine.audio.outputVolume = [[NSUserDefaults standardUserDefaults] floatForKey:@"outputVolume"];
        
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

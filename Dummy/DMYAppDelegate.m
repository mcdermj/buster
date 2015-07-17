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
    DMYDV3KVocoder *vocoder;
    DMYAudioHandler *audio;
}

@end

@implementation DMYAppDelegate

@synthesize network;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    NSURL *defaultPrefsFile = [[NSBundle mainBundle]
                               URLForResource:@"DefaultPreferences" withExtension:@"plist"];
    NSDictionary *defaultPrefs =
    [NSDictionary dictionaryWithContentsOfURL:defaultPrefsFile];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultPrefs];
    
    network = [[DMYGatewayHandler alloc] initWithRemoteAddress:[[NSUserDefaults standardUserDefaults] stringForKey:@"gatewayAddr"] remotePort:[[NSUserDefaults standardUserDefaults] integerForKey:@"gatewayPort"] localPort:20011];
    vocoder = [[DMYDV3KVocoder alloc] initWithPort:@"/dev/cu.usbserial-DA016UVB"];
    vocoder.speed = [[NSUserDefaults standardUserDefaults] integerForKey:@"dv3kSerialPortBaud"];
    audio = [[DMYAudioHandler alloc] init];
    
    
    network.xmitRepeater = [[NSUserDefaults standardUserDefaults] stringForKey:@"repeaterCall"];
    network.xmitMyCall = [[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"];
    
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

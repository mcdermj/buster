//
//  DMYAudioViewController.m
//
// Copyright (c) 2015 - Jeremy C. McDermond (NH6Z)

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

#import "DMYAudioViewController.h"

#import "DMYDataEngine.h"

@interface DMYAudioViewController ()
-(void)refreshDevices;
@end

@implementation DMYAudioViewController

@synthesize outputDeviceMenu;
@synthesize inputDeviceMenu;
@synthesize selectedInput;
@synthesize selectedOutput;

- (void) setSelectedInput:(NSInteger)_selectedInput {
    //DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];
    
    [DMYDataEngine sharedInstance].audio.inputDevice = (AudioDeviceID) _selectedInput;
    
    for(NSDictionary *entry in [DMYAudioHandler enumerateInputDevices])
        if(((NSNumber *)entry[@"id"]).integerValue == _selectedInput)
            [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"inputAudioDevice"];
}

- (NSInteger) selectedInput {
    //DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];
    
    return [DMYDataEngine sharedInstance].audio.inputDevice;
}

- (void) setSelectedOutput:(NSInteger)_selectedOutput {
    //DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];

    [DMYDataEngine sharedInstance].audio.outputDevice = (AudioDeviceID) _selectedOutput;
    
    for(NSDictionary *entry in [DMYAudioHandler enumerateOutputDevices])
        if(((NSNumber *)entry[@"id"]).integerValue == _selectedOutput)
            [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"outputAudioDevice"];

}

- (NSInteger)selectedOutput {
    //DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];
    
    return [DMYDataEngine sharedInstance].audio.outputDevice;
}

-(void)refreshDevices {
    //DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];

    NSLog(@"Refreshing devices");
    [inputDeviceMenu removeAllItems];
    for(NSDictionary *entry in [DMYAudioHandler enumerateInputDevices]) {
        [inputDeviceMenu addItemWithTitle:entry[@"description"]];
        [inputDeviceMenu itemWithTitle:entry[@"description"]].tag = ((NSNumber *)entry[@"id"]).integerValue;
        NSLog(@"Adding %@", entry[@"description"]);
    }
    [inputDeviceMenu selectItemWithTag:[DMYDataEngine sharedInstance].audio.inputDevice];
    
    [outputDeviceMenu removeAllItems];
    for(NSDictionary *entry in [DMYAudioHandler enumerateOutputDevices]) {
        [outputDeviceMenu addItemWithTitle:entry[@"description"]];
        [outputDeviceMenu itemWithTitle:entry[@"description"]].tag = ((NSNumber *)entry[@"id"]).integerValue;
    }
    [outputDeviceMenu selectItemWithTag:[DMYDataEngine sharedInstance].audio.outputDevice];
}

-(void)viewDidLoad {

    [self refreshDevices];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:DMYAudioDeviceChanged
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification){
                                                      [self refreshDevices];
                                                  }];
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DMYAudioDeviceChanged object:nil];
}

@end

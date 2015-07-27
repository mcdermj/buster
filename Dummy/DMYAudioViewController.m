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

- (void) setSelectedInput:(NSInteger)_selectedInput {
    [DMYDataEngine sharedInstance].audio.inputDevice = (AudioDeviceID) _selectedInput;
    
    for(NSDictionary *entry in [DMYAudioHandler enumerateInputDevices])
        if(((NSNumber *)entry[@"id"]).integerValue == _selectedInput)
            [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"inputAudioDevice"];
}

- (NSInteger) selectedInput {
    return [DMYDataEngine sharedInstance].audio.inputDevice;
}

- (void) setSelectedOutput:(NSInteger)_selectedOutput {
    [DMYDataEngine sharedInstance].audio.outputDevice = (AudioDeviceID) _selectedOutput;
    
    for(NSDictionary *entry in [DMYAudioHandler enumerateOutputDevices])
        if(((NSNumber *)entry[@"id"]).integerValue == _selectedOutput)
            [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"outputAudioDevice"];

}

- (NSInteger)selectedOutput {
    return [DMYDataEngine sharedInstance].audio.outputDevice;
}

-(void)refreshDevices {
    [self.inputDeviceMenu removeAllItems];
    for(NSDictionary *entry in [DMYAudioHandler enumerateInputDevices]) {
        [self.inputDeviceMenu addItemWithTitle:entry[@"description"]];
        [self.inputDeviceMenu itemWithTitle:entry[@"description"]].tag = ((NSNumber *)entry[@"id"]).integerValue;
    }
    [self.inputDeviceMenu selectItemWithTag:[DMYDataEngine sharedInstance].audio.inputDevice];
    
    [self.outputDeviceMenu removeAllItems];
    for(NSDictionary *entry in [DMYAudioHandler enumerateOutputDevices]) {
        [self.outputDeviceMenu addItemWithTitle:entry[@"description"]];
        [self.outputDeviceMenu itemWithTitle:entry[@"description"]].tag = ((NSNumber *)entry[@"id"]).integerValue;
    }
    [self.outputDeviceMenu selectItemWithTag:[DMYDataEngine sharedInstance].audio.outputDevice];
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

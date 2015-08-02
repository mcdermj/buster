//
//  BTRAudioViewController.m
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

#import "BTRAudioViewController.h"

#import "BTRDataEngine.h"

@interface BTRAudioViewController ()
-(void)refreshDevices;
@end

@implementation BTRAudioViewController

- (void) setSelectedInput:(NSInteger)_selectedInput {
    [BTRDataEngine sharedInstance].audio.inputDevice = (AudioDeviceID) _selectedInput;
    
    for(NSDictionary *entry in [BTRAudioHandler enumerateInputDevices])
        if(((NSNumber *)entry[@"id"]).integerValue == _selectedInput)
            [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"inputAudioDevice"];
}

- (NSInteger) selectedInput {
    return [BTRDataEngine sharedInstance].audio.inputDevice;
}

- (void) setSelectedOutput:(NSInteger)_selectedOutput {
    [BTRDataEngine sharedInstance].audio.outputDevice = (AudioDeviceID) _selectedOutput;
    
    for(NSDictionary *entry in [BTRAudioHandler enumerateOutputDevices])
        if(((NSNumber *)entry[@"id"]).integerValue == _selectedOutput)
            [[NSUserDefaults standardUserDefaults] setObject:entry[@"uid"] forKey:@"outputAudioDevice"];

}

- (NSInteger)selectedOutput {
    return [BTRDataEngine sharedInstance].audio.outputDevice;
}

-(void)refreshDevices {
    [self.inputDeviceMenu removeAllItems];
    for(NSDictionary *entry in [BTRAudioHandler enumerateInputDevices]) {
        [self.inputDeviceMenu addItemWithTitle:entry[@"description"]];
        [self.inputDeviceMenu itemWithTitle:entry[@"description"]].tag = ((NSNumber *)entry[@"id"]).integerValue;
    }
    [self.inputDeviceMenu selectItemWithTag:[BTRDataEngine sharedInstance].audio.inputDevice];
    
    [self.outputDeviceMenu removeAllItems];
    for(NSDictionary *entry in [BTRAudioHandler enumerateOutputDevices]) {
        [self.outputDeviceMenu addItemWithTitle:entry[@"description"]];
        [self.outputDeviceMenu itemWithTitle:entry[@"description"]].tag = ((NSNumber *)entry[@"id"]).integerValue;
    }
    [self.outputDeviceMenu selectItemWithTag:[BTRDataEngine sharedInstance].audio.outputDevice];
}

-(void)viewDidLoad {
    [self refreshDevices];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:BTRAudioDeviceChanged
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification){
                                                      [self refreshDevices];
                                                  }];
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:BTRAudioDeviceChanged object:nil];
}

@end

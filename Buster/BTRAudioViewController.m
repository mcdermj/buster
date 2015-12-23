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

#import "BTRAudioViewController.h"

#import "BTRDataEngine.h"
#import "BTRAudioHandler.h"

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

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

#import "DMYAppDelegate.h"

@interface DMYAudioViewController () {
    NSArray *inputDevices;
    NSArray *outputDevices;
}

@end

@implementation DMYAudioViewController

@synthesize outputDeviceMenu;
@synthesize inputDeviceMenu;
@synthesize selectedInput;
@synthesize selectedOutput;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
    }
    
    return self;
}

- (void) setSelectedInput:(NSInteger)_selectedInput {
    NSLog(@"Changed selected tag to %ld", (long)_selectedInput);
}

- (NSInteger) selectedInput {
    return 0;
}

-(void)viewDidLoad {
    inputDevices = [DMYAudioHandler enumerateInputDevices];
    outputDevices = [DMYAudioHandler enumerateOutputDevices];
}

- (void)viewDidAppear {
    // DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];
    
    [inputDeviceMenu removeAllItems];
    for(NSDictionary *deviceDescriptor in inputDevices) {
        [inputDeviceMenu addItemWithTitle:deviceDescriptor[@"name"]];
        [inputDeviceMenu itemWithTitle:deviceDescriptor[@"name"]].tag = ((NSNumber *) deviceDescriptor[@"id"]).integerValue;
    }
    
    [outputDeviceMenu removeAllItems];
    for(NSDictionary *deviceDescriptor in outputDevices) {
        [outputDeviceMenu addItemWithTitle:deviceDescriptor[@"name"]];
        [outputDeviceMenu itemWithTitle:deviceDescriptor[@"name"]].tag = ((NSNumber *) deviceDescriptor[@"id"]).integerValue;
    }

}

@end

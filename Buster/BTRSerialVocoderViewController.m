//
//  BTRSerialVocoderViewController.m
//
// Copyright (c) 2010-2015 - Jeremy C. McDermond (NH6Z)

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

#import "BTRSerialVocoderViewController.h"

#import "BTRDataEngine.h"
#import "BTRDV3KSerialVocoder.h"

@interface BTRSerialVocoderViewController ()
@end

@implementation BTRSerialVocoderViewController

- (id) init {
    self = [super initWithNibName:@"BTRSerialVocoderView" bundle:nil];
    
    return self;
}

-(void)viewDidLoad {
    NSLog(@"View Loaded");
}

- (void)viewDidAppear {
    [super viewDidAppear];
    
    [self refreshDevices];
    self.version.stringValue = self.driver.version;
    self.productId.stringValue = self.driver.productId;
    
    [self.speedPopup selectItemWithTitle:[NSString stringWithFormat:@"%ld", self.driver.speed]];
    [self.serialPortPopup selectItemWithTitle:self.driver.serialPort];
}

-(void)refreshDevices {
    [self.serialPortPopup removeAllItems];
    [self.serialPortPopup addItemsWithTitles:[BTRDV3KSerialVocoder ports]];
}

-(void)dealloc {
    NSLog(@"Deallocing");
}

-(IBAction)doChangeSerialPort:(id)sender {
    self.driver.serialPort = self.serialPortPopup.selectedItem.title;
    [[NSUserDefaults standardUserDefaults] setObject:self.driver.serialPort forKey:@"DV3KSerialVocoderPort"];
}

-(IBAction)doChangeSpeed:(id)sender {
    self.driver.speed = self.speedPopup.selectedItem.title.intValue;
    [[NSUserDefaults standardUserDefaults] setInteger:self.driver.speed forKey:@"DV3KSerialVocoderSpeed"];
}

@end

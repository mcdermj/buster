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

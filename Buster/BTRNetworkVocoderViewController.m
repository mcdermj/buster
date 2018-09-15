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
 * Copyright (c) 2015 Annaliese McDermond (NH6Z). All rights reserved.
 *
 */

#import "BTRNetworkVocoderViewController.h"

#import "BTRDV3KNetworkVocoder.h"
#import "BTRDataEngine.h"

@interface BTRNetworkVocoderViewController ()

@end

@implementation BTRNetworkVocoderViewController

- (id) init {
    self = [super initWithNibName:@"BTRNetworkVocoderView" bundle:nil];
    
    return self;
}

- (void) viewDidAppear {
    self.version.stringValue = self.driver.version;
    self.productId.stringValue = self.driver.productId;
}

-(void)dealloc {
    NSLog(@"Deallocing");
}

-(IBAction)doTest:(id)sender {
    [self.driver stop];
    [self.driver start];
}

@end

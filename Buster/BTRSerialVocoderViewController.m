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

/* - (void) bindAll {
    if([[BTRDataEngine sharedInstance].vocoder class] == [BTRDV3KSerialVocoder class]) {
        NSLog(@"Vocoder is a serial, we are going to bind");
        [self.productId bind:@"value" toObject:[BTRDataEngine sharedInstance].vocoder withKeyPath:@"productId" options:nil];
        [self.version bind:@"value" toObject:[BTRDataEngine sharedInstance].vocoder withKeyPath:@"version" options:nil];
    }
}

- (void) unbindAll {
    [self.productId unbind:@"value"];
    [self.version unbind:@"value"];
}

- (void) viewDidLoad {
    [[BTRDataEngine sharedInstance] addObserver:self forKeyPath:@"vocoder" options:NSKeyValueObservingOptionNew context:nil];
} */

- (void)viewDidAppear {
    [super viewDidAppear];
    
    [self refreshDevices];
    // [self bindAll];
}

-(void)refreshDevices {
    [self.serialPortPopup removeAllItems];
    [self.serialPortPopup addItemsWithTitles:[BTRDV3KSerialVocoder ports]];
}

/* - (void)viewWillDisappear {
    
    NSLog(@"Disappearing");
    [self unbindAll];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    NSLog(@"Change observed in vocoder");
    
    [self unbindAll];
    [self bindAll];
} */

-(void)dealloc {
    NSLog(@"Deallocing");
}

@end

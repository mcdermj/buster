//
//  BTRVocoderViewController.m
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

#import "BTRVocoderViewController.h"

#import "BTRDV3KSerialVocoder.h"
#import "BTRDV3KNetworkVocoder.h"
#import "BTRDataEngine.h"

@interface BTRVocoderViewController ()

@end

@implementation BTRVocoderViewController

- (void)viewDidLoad {
    
    NSUInteger serialIndex = [self.tabViewItems indexOfObjectPassingTest:^BOOL (id obj, NSUInteger idx, BOOL *stop) {
        NSTabViewItem *item = (NSTabViewItem *) obj;
        if([item.identifier isEqualToString:@"serial"])
            return YES;
        
        return NO;
    }];
    
    NSUInteger networkIndex = [self.tabViewItems indexOfObjectPassingTest:^BOOL (id obj, NSUInteger idx, BOOL *stop) {
        NSTabViewItem *item = (NSTabViewItem *) obj;
        if([item.identifier isEqualToString:@"network"])
            return YES;
        
        return NO;
    }];
    
    if([[BTRDataEngine sharedInstance].vocoder class] == [BTRDV3KSerialVocoder class]) {
        self.selectedTabViewItemIndex = serialIndex;
    } else if([[BTRDataEngine sharedInstance].vocoder class] == [BTRDV3KNetworkVocoder class]) {
        self.selectedTabViewItemIndex = networkIndex;
    }
    
    [super viewDidLoad];
    // Do view setup here.
}

- (void) replaceCurrentVocoderWith:(BTRDV3KVocoder *)vocoder {
    BTRDV3KVocoder *oldVocoder = [BTRDataEngine sharedInstance].vocoder;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [oldVocoder stop];
        [BTRDataEngine sharedInstance].vocoder = vocoder;
        [vocoder start];
        
    });
    
    for(NSString *binding in [oldVocoder exposedBindings])
        [oldVocoder unbind:binding];
}

- (void) tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    [super tabView:tabView didSelectTabViewItem:tabViewItem];
    
    if([tabViewItem.identifier isEqualToString:@"serial"]) {
        //  We got the serial vocoder here, do the initialization.
        if([[BTRDataEngine sharedInstance].vocoder class] == [BTRDV3KSerialVocoder class])
            return;
        
        BTRDV3KSerialVocoder *serialVocoder = [[BTRDV3KSerialVocoder alloc] init];
        [serialVocoder bind:@"speed" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.dv3kSerialPortBaud" options:nil];
        [serialVocoder bind:@"serialPort" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.dv3kSerialPort" options:nil];
        
        [self replaceCurrentVocoderWith:serialVocoder];
    } else if([tabViewItem.identifier isEqualToString:@"network"]) {
        //  We got the network vocoder here, do the initialization.
        if([[BTRDataEngine sharedInstance].vocoder class] == [BTRDV3KNetworkVocoder class])
            return;

        BTRDV3KNetworkVocoder *networkVocoder = [[BTRDV3KNetworkVocoder alloc] init];
        [networkVocoder bind:@"address" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.dv3kNetworkAddress" options:nil];
        [networkVocoder bind:@"port" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.dv3kNetworkPort" options:nil];
        
        [self replaceCurrentVocoderWith:networkVocoder];
    }
}

@end

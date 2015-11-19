//
//  BTRNetworkVocoderViewController.m
//  Buster
//
//  Created by Jeremy McDermond on 8/4/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

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

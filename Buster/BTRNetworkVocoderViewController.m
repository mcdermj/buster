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

-(void)dealloc {
    NSLog(@"Deallocing");
}

@end

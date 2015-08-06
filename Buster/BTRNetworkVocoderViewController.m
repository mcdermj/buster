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
- (void) bindAll {
    if([[BTRDataEngine sharedInstance].vocoder class] == [BTRDV3KNetworkVocoder class]) {
        NSLog(@"Vocoder is a network, we are going to bind");
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
}

- (void)viewDidAppear {
    [super viewDidAppear];
    
    [self bindAll];
}

- (void)viewWillDisappear {
    NSLog(@"Disappearing");
    [self unbindAll];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    NSLog(@"Change observed in vocoder");
    
    [self unbindAll];
    [self bindAll];
}

@end

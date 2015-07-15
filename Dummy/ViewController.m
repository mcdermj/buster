//
//  ViewController.m
//  Dummy
//
//  Created by Jeremy McDermond on 7/10/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "ViewController.h"

@implementation ViewController

@synthesize myCall;
@synthesize urCall;
@synthesize rpt1Call;
@synthesize rpt2Call;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    __weak ViewController *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYNetworkHeaderReceived
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification) {
                                                      DMYGatewayHandler *networkObject = [notification object];
                                                      weakSelf.myCall.stringValue = networkObject.myCall;
                                                      weakSelf.urCall.stringValue = networkObject.urCall;
                                                      weakSelf.rpt1Call.stringValue = networkObject.rpt1Call;
                                                      weakSelf.rpt2Call.stringValue = networkObject.rpt2Call;
                                                  }
     ];
    
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYNetworkStreamEnd
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock: ^(NSNotification *notification) {
                                                      weakSelf.myCall.stringValue = @"";
                                                      weakSelf.urCall.stringValue = @"";
                                                      weakSelf.rpt1Call.stringValue = @"";
                                                      weakSelf.rpt2Call.stringValue = @"";
                                                  }
     ];

    // Do any additional setup after loading the view.
}

- (void)viewWillDisappear {
    NSLog(@"View Dissapearing\n");
    
    /* [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:DMYNetworkHeaderReceived
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:DMYNetworkStreamEnd
                                                  object: nil]; */
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    // Update the view, if already loaded.
}

@end

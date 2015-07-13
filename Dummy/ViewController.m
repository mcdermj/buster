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
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYNetworkHeaderReceived
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification) {
                                                      DMYGatewayHandler *networkObject = [notification object];
                                                      myCall.stringValue = networkObject.myCall;
                                                      urCall.stringValue = networkObject.urCall;
                                                      rpt1Call.stringValue = networkObject.rpt1Call;
                                                      rpt2Call.stringValue = networkObject.rpt2Call;
                                                  }
     ];
    
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYNetworkStreamEnd
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock: ^(NSNotification *notification) {
                                                      myCall.stringValue = @"";
                                                      urCall.stringValue = @"";
                                                      rpt1Call.stringValue = @"";
                                                      rpt2Call.stringValue = @"";
                                                  }
     ];

    // Do any additional setup after loading the view.
}

- (void)viewWillDisappear {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:DMYNetworkHeaderReceived
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:DMYNetworkStreamEnd
                                                  object: nil];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    // Update the view, if already loaded.
}

@end

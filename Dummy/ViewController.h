//
//  ViewController.h
//  Dummy
//
//  Created by Jeremy McDermond on 7/10/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ViewController : NSViewController

@property (weak) IBOutlet NSTextField *urCall;
@property (weak) IBOutlet NSTextField *myCall;
@property (weak) IBOutlet NSTextField *rpt1Call;
@property (weak) IBOutlet NSTextField *rpt2Call;
@property (weak) IBOutlet NSTextField *linkTarget;

- (IBAction)doLink:(id)sender;

@end


//
//  BTRNetworkVocoderViewController.h
//  Buster
//
//  Created by Jeremy McDermond on 8/4/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

@class BTRDV3KNetworkVocoder;

@interface BTRNetworkVocoderViewController : NSViewController

@property (weak) IBOutlet NSTextField *productId;
@property (weak) IBOutlet NSTextField *version;
@property (weak) BTRDV3KNetworkVocoder *driver;

-(IBAction)doTest:(id)sender;
@end

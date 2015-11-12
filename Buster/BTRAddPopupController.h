//
//  BTRAddPopupController.h
//  Buster
//
//  Created by Jeremy McDermond on 9/29/15.
//  Copyright © 2015 NH6Z. All rights reserved.
//

@interface BTRAddPopupController : NSViewController <NSControlTextEditingDelegate, NSPopoverDelegate>

@property (nonatomic) NSArrayController *reflectorArrayController;
@property (weak) IBOutlet NSTextFieldCell *destinationField;
@property (weak) IBOutlet NSPopUpButton *moduleField;

- (IBAction)doAdd:(id)sender;

@end

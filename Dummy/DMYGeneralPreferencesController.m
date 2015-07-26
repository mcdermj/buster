//
//  DMYGeneralPreferencesController.m
//  Dummy
//
//  Created by Jeremy McDermond on 7/25/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "DMYGeneralPreferencesController.h"

@interface DMYGeneralPreferencesController ()

@end

@implementation DMYGeneralPreferencesController

@synthesize shortcutView;
@synthesize shortcutValue;

-(void) setShortcutValue:(MASShortcut *)_value {
    shortcutValue = _value;
    
    NSLog(@"Shortcut is %lu", (unsigned long)shortcutValue.keyCode);
}

-(MASShortcut *)shortcutValue {
    return shortcutValue;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    
    //[shortcutView bind:@"shortcutValue" toObject:self withKeyPath:@"shortcutValue" options:nil];
    [shortcutView bind:@"shortcutValue" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.shortcutValue" options:@{NSValueTransformerNameBindingOption: MASDictionaryTransformerName}];
}

@end

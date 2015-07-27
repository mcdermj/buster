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

-(void) setShortcutValue:(MASShortcut *)value {
    _shortcutValue = value;    
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.shortcutView bind:@"shortcutValue" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.shortcutValue" options:@{NSValueTransformerNameBindingOption: MASDictionaryTransformerName}];
}

@end

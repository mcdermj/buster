//
//  DMYGeneralPreferencesController.h
//  Dummy
//
//  Created by Jeremy McDermond on 7/25/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import <MASShortcut/Shortcut.h>

@interface DMYGeneralPreferencesController : NSViewController

@property (nonatomic, weak) IBOutlet MASShortcutView *shortcutView;
@property (nonatomic) MASShortcut *shortcutValue;
@end

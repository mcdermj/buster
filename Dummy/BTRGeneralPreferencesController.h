//
//  BTRGeneralPreferencesController.h
//  Dummy
//
//  Created by Jeremy McDermond on 7/25/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

@class MASShortcut, MASShortcutView;

@interface BTRGeneralPreferencesController : NSViewController

@property (nonatomic, weak) IBOutlet MASShortcutView *shortcutView;
@property (nonatomic) MASShortcut *shortcutValue;
@end

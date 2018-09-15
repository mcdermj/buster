/*
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at
 * https://solaris.java.net/license.html
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at
 * https://solaris.java.net/license.html.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
 * License for the specific language governing permissions and limitations under
 * the License.
 *
 * Copyright (c) 2015 Annaliese McDermond (NH6Z). All rights reserved.
 *
 */

#import "BTRDataEngineDelegate.h"

@class MASShortcut;

@interface BTRMainWindowViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource, NSControlTextEditingDelegate, BTRDataEngineDelegate>

@property (nonatomic, strong) IBOutlet NSArrayController *heardTableController;
@property (nonatomic, weak) IBOutlet NSTableView *heardTableView;
@property (nonatomic, weak) IBOutlet NSTableView *reflectorTableView;
@property (nonatomic, strong) IBOutlet NSArrayController *reflectorTableController;
@property (nonatomic, weak) IBOutlet NSImageView *statusLED;
@property (nonatomic, weak) IBOutlet NSButton *txButton;
@property (nonatomic, weak) IBOutlet NSTextField *repeaterInfo;
@property (nonatomic, readonly) NSMutableArray <NSMutableDictionary *> *qsoList;
@property MASShortcut *txKeyCode;
@property (weak) IBOutlet NSSlider *volumeSlider;


- (IBAction)doReflectorDoubleClick:(id)sender;
- (IBAction)doHeardDoubleClick:(id)sender;
- (IBAction)doLink:(id)sender;
- (IBAction)addReflector:(id)sender;
- (IBAction)doTx:(id)sender;
- (IBAction)doUnlink:(id)sender;
- (IBAction)doVolumeChange:(id)sender;

@end


//
//  BTRMainWindowViewController.h
//
//  Copyright (c) 2015 - Jeremy C. McDermond (NH6Z)

// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

@interface BTRMainWindowViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource, NSControlTextEditingDelegate>

@property (nonatomic, weak) IBOutlet NSTextField *urCall;
@property (nonatomic, weak) IBOutlet NSTextField *myCall;
@property (nonatomic, weak) IBOutlet NSTextField *rpt1Call;
@property (nonatomic, weak) IBOutlet NSTextField *rpt2Call;
@property (nonatomic, weak) IBOutlet NSTextField *linkTarget;
@property (nonatomic, strong) IBOutlet NSArrayController *heardTableController;
@property (nonatomic, weak) IBOutlet NSTableView *heardTableView;
@property (nonatomic, weak) IBOutlet NSTableView *reflectorTableView;
@property (nonatomic, strong) IBOutlet NSArrayController *reflectorTableController;
@property (nonatomic, weak) IBOutlet NSComboBox *xmitUrCall;
@property (nonatomic, weak) IBOutlet NSImageView *statusLED;
@property (nonatomic, weak) IBOutlet NSButton *txButton;
@property (nonatomic, weak) IBOutlet NSTextField *repeaterInfo;
@property (nonatomic, weak) IBOutlet NSTextField *shortTextMessageField;

- (IBAction)doLink:(id)sender;
- (IBAction)addReflector:(id)sender;
- (IBAction)doTx:(id)sender;
- (IBAction)doUnlink:(id)sender;

@end


//
//  DMYMainWindowViewController.m
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

#import "DMYMainWindowViewController.h"

#import "DMYGatewayHandler.h"
#import "DMYAppDelegate.h"

@interface DMYMainWindowViewController () {
    NSInteger txButtonState;
}
@end

@implementation DMYMainWindowViewController

@synthesize myCall;
@synthesize urCall;
@synthesize rpt1Call;
@synthesize rpt2Call;
@synthesize linkTarget;
@synthesize heardTableController;
@synthesize heardTableView;
@synthesize reflectorTableView;
@synthesize reflectorTableController;
@synthesize xmitUrCall;
@synthesize statusLED;
@synthesize txButton;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];
    
    [reflectorTableView registerForDraggedTypes:@[ @"com.nh6z.Dummy.reflector" ]];
    reflectorTableView.dataSource = self;
    
    heardTableView.delegate = self;
    heardTableController.sortDescriptors = @[ [[NSSortDescriptor alloc] initWithKey:@"time" ascending:NO] ];
    
    __weak DMYMainWindowViewController *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYNetworkStreamStart
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification) {
                                                                                                            
                                                      weakSelf.urCall.stringValue = notification.userInfo[@"urCall"];
                                                      weakSelf.myCall.stringValue = notification.userInfo[@"myCall"];
                                                      weakSelf.rpt1Call.stringValue = notification.userInfo[@"rpt1Call"];
                                                      weakSelf.rpt2Call.stringValue = notification.userInfo[@"rpt2Call"];
                                                     
                                                      NSPredicate *currentFilterPredicate = heardTableController.filterPredicate;
                                                      heardTableController.filterPredicate = nil;
                                                      
                                                      NSPredicate *streamIdPredicate = [NSPredicate predicateWithFormat:@"streamId == %@", notification.userInfo[@"streamId"]];
                                                      NSArray *entries = [heardTableController.arrangedObjects filteredArrayUsingPredicate:streamIdPredicate];
                                                                                                                                              
                                                      if(entries.count == 0)
                                                          [heardTableController addObject:notification.userInfo];
                                                      
                                                      heardTableController.filterPredicate = currentFilterPredicate;
                                                      
                                                      statusLED.image = [NSImage imageNamed:@"Green LED"];
                                                  }
     ];
    
    [[NSNotificationCenter defaultCenter] addObserverForName: DMYNetworkStreamEnd
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock: ^(NSNotification *notification) {                                                      
                                                      weakSelf.myCall.stringValue = @"";
                                                      weakSelf.urCall.stringValue = @"";
                                                      weakSelf.rpt1Call.stringValue = @"";
                                                      weakSelf.rpt2Call.stringValue = @"";
                                                      
                                                      NSPredicate *currentFilterPredicate = heardTableController.filterPredicate;
                                                      heardTableController.filterPredicate = nil;
                                                      
                                                      NSPredicate *streamIdPredicate = [NSPredicate predicateWithFormat:@"streamId == %@", notification.userInfo[@"streamId"]];
                                                      NSArray *entries = [heardTableController.arrangedObjects filteredArrayUsingPredicate:streamIdPredicate];
                                                      
                                                      if(entries.count != 1) {
                                                          NSLog(@"Found a freaky number of entries for predicate: %lu\n", (unsigned long)entries.count);
                                                          return;
                                                      }

                                                      NSDate *headerTime = notification.userInfo[@"time"];
                                                      NSDate *startTime = entries[0][@"time"];
                                                      NSMutableDictionary *newHeader = [NSMutableDictionary dictionaryWithDictionary:entries[0]];
                                                      newHeader[@"duration"] = [NSNumber numberWithDouble:[headerTime timeIntervalSinceDate:startTime]];
                                                      
                                                      [heardTableController removeObject:entries[0]];
                                                      [heardTableController addObject:[NSDictionary dictionaryWithDictionary:newHeader]];
                                                      
                                                      heardTableController.filterPredicate = currentFilterPredicate;
                                                      
                                                      statusLED.image = [NSImage imageNamed:@"Gray LED"];
                                                  }
     ];
    
    [txButton setPeriodicDelay:.1f interval:.1f];
    txButtonState = NSOffState;
    
    //[xmitUrCall bind:@"value" toObject:delegate.network withKeyPath:@"xmitUrCall" options:nil];
    //[delegate.network bind:@"xmitUrCall" toObject:xmitUrCall withKeyPath:@"value" options:nil];
}

- (void)viewWillDisappear {
    NSLog(@"View Dissapearing\n");
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:DMYNetworkHeaderReceived
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:DMYNetworkStreamEnd
                                                  object:nil];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    // Update the view, if already loaded.
}

- (IBAction)doLink:(id)sender {
    DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];
    
    if(reflectorTableController.selectedObjects.count != 1) {
        NSBeep();
        return;
    }

    NSString *reflector = reflectorTableController.selectedObjects[0][@"reflector"];
    
    if(reflector.length < 8)
        return;
    
    [delegate.network linkTo:reflector];
}

-(void) addReflector:(id)sender {
    NSMutableDictionary *newObject = [NSMutableDictionary dictionaryWithDictionary:@{ @"reflector": @"REFXXX C"}];
    [reflectorTableController addObject:newObject];
    
    NSInteger insertedObjectIndex = [reflectorTableController.arrangedObjects indexOfObject:newObject];
    reflectorTableController.selectionIndex = insertedObjectIndex;
    [reflectorTableView editColumn:0 row:insertedObjectIndex withEvent:nil select:YES];
}

- (IBAction)reflectorTableEnter:(id)sender {
    NSLog(@"I'm here\n");
}

- (IBAction)doTx:(id)sender {
    DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];
    // NSButton *txButton = (NSButton *)sender;
    
    
    
    if(txButton.state == txButtonState) {
        delegate.network.xmitUrCall = xmitUrCall.objectValue;
        delegate.audio.xmit = YES;
        statusLED.image = [NSImage imageNamed:@"Red LED"];
    } else {
        delegate.audio.xmit = NO;
        delegate.network.xmitUrCall = @"";
        statusLED.image = [NSImage imageNamed:@"Gray LED"];
    }
    
    txButtonState = txButton.state;
    
    /* if(delegate.audio.xmit) {
        delegate.audio.xmit = NO;
        delegate.network.xmitUrCall = @"";
        statusLED.image = [NSImage imageNamed:@"Gray LED"];
    }  else {
        delegate.network.xmitUrCall = xmitUrCall.objectValue;
        delegate.audio.xmit = YES;
        statusLED.image = [NSImage imageNamed:@"Red LED"];
     } */
}

- (IBAction)doUnlink:(id)sender {
    DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];

    [delegate.network unlink];
}

#pragma mark - Selection Control

- (NSIndexSet *) tableView:(NSTableView *)tableView selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes {
    if(tableView == heardTableView)
        return nil;
    
    return proposedSelectionIndexes;
}

#pragma mark - Drag and Drop support

- (id <NSPasteboardWriting>) tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSDictionary *reflector = reflectorTableController.arrangedObjects[row];
    
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setPropertyList:reflector forType:@"com.nh6z.Dummy.reflector"];
    
    return item;
}

-(NSDragOperation) tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

-(BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
    NSDictionary *reflector = [info.draggingPasteboard propertyListForType:@"com.nh6z.Dummy.reflector"];
    
    if(tableView != reflectorTableView)
        return NO;
    
    NSInteger oldIndex = [reflectorTableController.arrangedObjects indexOfObject:reflector];
    
    [reflectorTableController removeObject:reflector];
    if(row < oldIndex)
        [reflectorTableController insertObject:reflector atArrangedObjectIndex:row];
    else
        [reflectorTableController insertObject:reflector atArrangedObjectIndex:row - 1];
    
    return YES;
}

/* - (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    NSArray *objects = reflectorTableController.arrangedObjects;
    
    NSLog(@"%ld  -- objects = %@", objects.count, objects);
    
    return [objects count];
}


- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSLog(@"Need cell for row %ld column %@", row, tableColumn);
    return nil;
} */

@end

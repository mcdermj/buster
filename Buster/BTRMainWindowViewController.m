//
//  BTRMainWindowViewController.m
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

#import "BTRMainWindowViewController.h"

#import "BTRApplication.h"
#import "BTRDataEngine.h"
#import "BTRSlowDataCoder.h"
#import "BTRAudioHandler.h"

@interface BTRMainWindowViewController () {
    NSInteger txButtonState;
}

@end

@implementation BTRMainWindowViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.reflectorTableView registerForDraggedTypes:@[ @"net.nh6z.Dummy.reflector" ]];
    self.reflectorTableView.dataSource = self;
    
    self.heardTableView.delegate = self;
    self.heardTableController.sortDescriptors = @[ [[NSSortDescriptor alloc] initWithKey:@"time" ascending:NO] ];
    
    __weak BTRMainWindowViewController *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName: BTRNetworkStreamStart
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification) {
                                                      NSMutableDictionary *header = [NSMutableDictionary dictionaryWithDictionary:notification.userInfo];
                                                      
                                                      if([((NSString *)header[@"myCall2"]) isEqualToString:@"    "])
                                                          header[@"compositeMyCall"] = header[@"myCall"];
                                                      else
                                                          header[@"compositeMyCall"] = [NSString stringWithFormat:@"%@/%@", [header[@"myCall"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]], [header[@"myCall2"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
                                                      
                                                      
                                                      weakSelf.myCall.stringValue = header[@"compositeMyCall"];
                                                      weakSelf.urCall.stringValue = header[@"urCall"];
                                                      weakSelf.rpt1Call.stringValue = header[@"rpt1Call"];
                                                      weakSelf.rpt2Call.stringValue = header[@"rpt2Call"];
                                                     
                                                      NSPredicate *currentFilterPredicate = self.heardTableController.filterPredicate;
                                                      self.heardTableController.filterPredicate = nil;
                                                      
                                                      NSPredicate *streamIdPredicate = [NSPredicate predicateWithFormat:@"streamId == %@", header[@"streamId"]];
                                                      NSArray *entries = [self.heardTableController.arrangedObjects filteredArrayUsingPredicate:streamIdPredicate];
                                                                                                                                              
                                                      if(entries.count == 0)
                                                          [self.heardTableController addObject:header];
                                                      
                                                      self.heardTableController.filterPredicate = currentFilterPredicate;
                                                      
                                                      self.statusLED.image = [NSImage imageNamed:@"Green LED"];
                                                  }
     ];
    
    [[NSNotificationCenter defaultCenter] addObserverForName: BTRNetworkStreamEnd
                                                      object: nil
                                                       queue: [NSOperationQueue mainQueue]
                                                  usingBlock: ^(NSNotification *notification) {                                                      
                                                      weakSelf.myCall.stringValue = @"";
                                                      weakSelf.urCall.stringValue = @"";
                                                      weakSelf.rpt1Call.stringValue = @"";
                                                      weakSelf.rpt2Call.stringValue = @"";
                                                      weakSelf.shortTextMessageField.stringValue = @"";
                                                      
                                                      NSPredicate *currentFilterPredicate = self.heardTableController.filterPredicate;
                                                      self.heardTableController.filterPredicate = nil;
                                                      
                                                      NSPredicate *streamIdPredicate = [NSPredicate predicateWithFormat:@"streamId == %@", notification.userInfo[@"streamId"]];
                                                      NSArray *entries = [self.heardTableController.arrangedObjects filteredArrayUsingPredicate:streamIdPredicate];
                                                      
                                                      if(entries.count != 1) {
                                                          NSLog(@"Found a freaky number of entries for predicate: %lu\n", (unsigned long)entries.count);
                                                          self.heardTableController.filterPredicate = currentFilterPredicate;
                                                          return;
                                                      }

                                                      NSDate *headerTime = notification.userInfo[@"time"];
                                                      NSDate *startTime = entries[0][@"time"];
                                                      NSMutableDictionary *newHeader = [NSMutableDictionary dictionaryWithDictionary:entries[0]];
                                                      newHeader[@"duration"] = [NSNumber numberWithDouble:[headerTime timeIntervalSinceDate:startTime]];
                                                      
                                                      [self.heardTableController removeObject:entries[0]];
                                                      [self.heardTableController addObject:[NSDictionary dictionaryWithDictionary:newHeader]];
                                                      
                                                      self.heardTableController.filterPredicate = currentFilterPredicate;
                                                      
                                                      self.statusLED.image = [NSImage imageNamed:@"Gray LED"];
                                                  }
     ];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:BTRTxKeyDown object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
        [self startTx];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:BTRTxKeyUp object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
        [self endTx];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:BTRRepeaterInfoReceived object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
        self.repeaterInfo.stringValue = notification.userInfo[@"local"];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:BTRSlowDataTextReceived object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification){
        self.shortTextMessageField.stringValue = notification.userInfo[@"text"];
        
        NSPredicate *currentFilterPredicate = self.heardTableController.filterPredicate;
        self.heardTableController.filterPredicate = nil;
        
        NSPredicate *streamIdPredicate = [NSPredicate predicateWithFormat:@"streamId == %@", notification.userInfo[@"streamId"]];
        NSArray *entries = [self.heardTableController.arrangedObjects filteredArrayUsingPredicate:streamIdPredicate];
        
        if(entries.count != 1) {
            NSLog(@"Found a freaky number of entries for streamId %@: %lu\n", notification.userInfo[@"streamId"], (unsigned long)entries.count);
            self.heardTableController.filterPredicate = currentFilterPredicate;
            return;
        }
        
        NSMutableDictionary *newHeader = [NSMutableDictionary dictionaryWithDictionary:entries[0]];
        newHeader[@"message"] = notification.userInfo[@"text"];
        
        [self.heardTableController removeObject:entries[0]];
        [self.heardTableController addObject:[NSDictionary dictionaryWithDictionary:newHeader]];
        
        self.heardTableController.filterPredicate = currentFilterPredicate;
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:BTRNetworkLinkFailed object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = notification.userInfo[@"error"];
        [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response){ }];
    }];

    
    [self.txButton setPeriodicDelay:.1f interval:.1f];
    txButtonState = NSOffState;
}

- (void)viewWillDisappear {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:BTRNetworkHeaderReceived
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:BTRNetworkStreamEnd
                                                  object:nil];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
}

- (IBAction)doLink:(id)sender {
    if(self.reflectorTableController.selectedObjects.count != 1) {
        NSBeep();
        return;
    }

    NSString *reflector = self.reflectorTableController.selectedObjects[0][@"reflector"];
    
    if(reflector.length < 8)
        return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [[BTRDataEngine sharedInstance] linkTo:reflector];
    });
}

- (IBAction)doUnlink:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [[BTRDataEngine sharedInstance] unlink];
    });
}


-(void) addReflector:(id)sender {
    NSMutableDictionary *newObject = [NSMutableDictionary dictionaryWithDictionary:@{ @"reflector": @"REFXXX C" }];
    [self.reflectorTableController addObject:newObject];
    
    NSInteger insertedObjectIndex = [self.reflectorTableController.arrangedObjects indexOfObject:newObject];
    self.reflectorTableController.selectionIndex = insertedObjectIndex;
    [self.reflectorTableView editColumn:0 row:insertedObjectIndex withEvent:nil select:YES];
}

-(void)startTx {
    if(self.xmitUrCall.objectValue == nil)
        return;
    
    [self.view.window makeFirstResponder:nil];
    
    //[BTRDataEngine sharedInstance].network.xmitUrCall = self.xmitUrCall.objectValue;
    [BTRDataEngine sharedInstance].audio.xmit = YES;
    self.statusLED.image = [NSImage imageNamed:@"Red LED"];
    
    NSMutableArray *destinationCalls = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"destinationCalls"]];
    if (![destinationCalls containsObject:self.xmitUrCall.objectValue]) {
        if(destinationCalls.count > 11) {
            [destinationCalls removeObjectAtIndex:11];
        }
        [destinationCalls insertObject:self.xmitUrCall.objectValue atIndex:1];
        [[NSUserDefaults standardUserDefaults] setObject:destinationCalls forKey:@"destinationCalls"];
    }
}

-(void)endTx {
    [BTRDataEngine sharedInstance].audio.xmit = NO;
    //[BTRDataEngine sharedInstance].network.xmitUrCall = @"";
    self.statusLED.image = [NSImage imageNamed:@"Gray LED"];
}

- (IBAction)doTx:(id)sender {    
    if(self.txButton.state == txButtonState)
        [self startTx];
    else
        [self endTx];
    
    txButtonState = self.txButton.state;
}

#pragma mark - Text Editing Control

-(BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor {
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [control.window makeFirstResponder:nil];
    });
    return YES;
}

#pragma mark - Selection Control

- (NSIndexSet *) tableView:(NSTableView *)tableView selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes {
    if(tableView == self.heardTableView)
        return nil;
    
    return proposedSelectionIndexes;
}

#pragma mark - Drag and Drop support

- (id <NSPasteboardWriting>) tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSDictionary *reflector = self.reflectorTableController.arrangedObjects[row];
    
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setPropertyList:reflector forType:@"net.nh6z.Dummy.reflector"];
    
    return item;
}

-(NSDragOperation) tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

-(BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
    NSDictionary *reflector = [info.draggingPasteboard propertyListForType:@"net.nh6z.Dummy.reflector"];
    
    if(tableView != self.reflectorTableView)
        return NO;
    
    NSInteger oldIndex = [self.reflectorTableController.arrangedObjects indexOfObject:reflector];
    
    [self.reflectorTableController removeObject:reflector];
    if(row < oldIndex)
        [self.reflectorTableController insertObject:reflector atArrangedObjectIndex:row];
    else
        [self.reflectorTableController insertObject:reflector atArrangedObjectIndex:row - 1];
    
    return YES;
}

#pragma mark - Reflector cell validation

-(BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error {
    if(control != self.reflectorTableView) {
        NSLog(@"Control is not reflector list");
        return NO;
    }
    NSLog(@"Reflector string is invalid: %@", string);
    
    [self.reflectorTableController remove:string];
    
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = error;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response){ }];
    
    return YES;
}

@end

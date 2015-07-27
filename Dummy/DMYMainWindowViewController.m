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
#import "DMYApplication.h"
#import "DMYDataEngine.h"

@interface DMYMainWindowViewController () {
    NSInteger txButtonState;
}

@property DMYGatewayHandler *network;

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
    //DMYDataEngine *engine = [DMYDataEngine sharedInstance];
    
    _network = [DMYDataEngine sharedInstance].network;
    
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
    
    [[NSNotificationCenter defaultCenter] addObserverForName:DMYTxKeyDown object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
        [self startTx];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:DMYTxKeyUp object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
        [self endTx];
    }];
    
    [txButton setPeriodicDelay:.1f interval:.1f];
    txButtonState = NSOffState;    
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
}

- (IBAction)doLink:(id)sender {
    //DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];
    
    if(reflectorTableController.selectedObjects.count != 1) {
        NSBeep();
        return;
    }

    NSString *reflector = reflectorTableController.selectedObjects[0][@"reflector"];
    
    if(reflector.length < 8)
        return;
    
    [[DMYDataEngine sharedInstance].network linkTo:reflector];
}

-(void) addReflector:(id)sender {
    NSMutableDictionary *newObject = [NSMutableDictionary dictionaryWithDictionary:@{ @"reflector": @"REFXXX C"}];
    [reflectorTableController addObject:newObject];
    
    NSInteger insertedObjectIndex = [reflectorTableController.arrangedObjects indexOfObject:newObject];
    reflectorTableController.selectionIndex = insertedObjectIndex;
    [reflectorTableView editColumn:0 row:insertedObjectIndex withEvent:nil select:YES];
}

-(void)startTx {
    [DMYDataEngine sharedInstance].network.xmitUrCall = xmitUrCall.objectValue;
    [DMYDataEngine sharedInstance].audio.xmit = YES;
    statusLED.image = [NSImage imageNamed:@"Red LED"];
    //  [window makeFirstResponder:nil];
    
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
    [DMYDataEngine sharedInstance].audio.xmit = NO;
    [DMYDataEngine sharedInstance].network.xmitUrCall = @"";
    statusLED.image = [NSImage imageNamed:@"Gray LED"];
}

- (IBAction)doTx:(id)sender {    
    if(txButton.state == txButtonState)
        [self startTx];
    else
        [self endTx];
    
    txButtonState = txButton.state;
}

- (IBAction)doUnlink:(id)sender {
    //DMYAppDelegate *delegate = (DMYAppDelegate *) [NSApp delegate];

    [[DMYDataEngine sharedInstance].network unlink];
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

-(void)keyDown:(NSEvent *) event {
    NSLog(@"Got KeyDown");
}

@end

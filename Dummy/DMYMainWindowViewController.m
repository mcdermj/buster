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

@interface DMYMainWindowViewController ()
- (void) linkReflector:(id)sender;
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

- (void) linkReflector:(id)sender {
    NSString *reflector = [reflectorTableView.dataSource tableView:reflectorTableView objectValueForTableColumn:0 row:reflectorTableView.clickedRow];
    NSLog(@"Reflector %@ double clicked\n", reflector);
}

- (void)viewDidLoad {
    [super viewDidLoad];
        
    // XXX This is cruddy.  Why are there blank entries in there anyhow?
    for(NSDictionary *entry in heardTableController.arrangedObjects)
        if(entry.count == 0)
            [heardTableController removeObject:entry];
    
    heardTableView.delegate = self;
    heardTableController.sortDescriptors = @[ [[NSSortDescriptor alloc] initWithKey:@"time" ascending:NO] ];
    
    reflectorTableView.doubleAction = @selector(linkReflector:);
    
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
                                                      
                                                      // XXX This is cruddy.  Why are there blank entries in there anyhow?
                                                      for(NSDictionary *entry in heardTableController.arrangedObjects)
                                                          if(entry.count == 0)
                                                              [heardTableController removeObject:entry];
                                                      
                                                      NSPredicate *streamIdPredicate = [NSPredicate predicateWithFormat:@"streamId == %@", notification.userInfo[@"streamId"]];
                                                      NSArray *entries = [heardTableController.arrangedObjects filteredArrayUsingPredicate:streamIdPredicate];
                                                                                                                                              
                                                      if(entries.count == 0)
                                                          [heardTableController addObject:notification.userInfo];
                                                      
                                                      heardTableController.filterPredicate = currentFilterPredicate;
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
                                                  }
     ];
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
    
    if(reflectorTableController.selectedObjects.count != 1)
        return;

    NSString *reflector = reflectorTableController.selectedObjects[0][@"reflector"];
    
    if(reflector.length < 8)
        return;
    
    [delegate.network linkTo:reflector];
}

- (NSIndexSet *) tableView:(NSTableView *)tableView selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes {
    return nil;
}

@end

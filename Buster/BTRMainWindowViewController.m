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
 * Copyright (c) 2015 Jeremy McDermond (NH6Z). All rights reserved.
 *
 */

#import "BTRMainWindowViewController.h"

#import "BTRAppDelegate.h"
#import "MASShortcut.h"
#import "MASDictionaryTransformer.h"
#import "BTRDataEngine.h"
#import "BTRSlowDataCoder.h"
#import "BTRAudioHandler.h"
#import "BTRMapPopupController.h"
#import "BTRAprsLocation.h"
#import "BTRAddPopupController.h"


@import MapKit;

@interface BTRMainWindowViewController ()

@property (nonatomic) dispatch_source_t qsoTimer;
@property (nonatomic) NSInteger txButtonState;
@property (nonatomic) NSSpeechSynthesizer *speechSynth;
@property (nonatomic) CLGeocoder *geocoder;
@property (nonatomic, readwrite) NSMutableArray <NSMutableDictionary *> *qsoList;
@property (nonatomic) NSPopover *mapPopover;
@property (nonatomic) NSPopover *addPopover;


@end

@implementation BTRMainWindowViewController

+(NSUInteger)findQsoId:(NSNumber *)streamId inArray:(NSArray *)array {
    return [array indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        NSDictionary *entry = (NSDictionary *) obj;
        if(streamId && [((NSNumber *)entry[@"streamId"]) isEqualToNumber:streamId]) {
            *stop = YES;
            return YES;
        }
        
        return NO;
    }];
}

-(BOOL)updateQsoId:(NSNumber *)streamId usingBlock:(void(^)(NSMutableDictionary *, NSUInteger))block {
    NSUInteger qsoIndex = [BTRMainWindowViewController findQsoId:streamId inArray:self.qsoList];
    if(qsoIndex == NSNotFound)
        return NO;

    NSMutableDictionary *qso = self.qsoList[qsoIndex];
    block(qso, qsoIndex);
    
    return YES;
}

// XXX These probably shouldn't be called "headers" anymore.  They're really stream info dictionaries.
-(void)streamDidStart:(NSDictionary *)inHeader {
    NSMutableDictionary *header = [NSMutableDictionary dictionaryWithDictionary:inHeader];
    
    if([((NSString *)header[@"myCall2"]) isEqualToString:@""])
        header[@"compositeMyCall"] = header[@"myCall"];
    else
        header[@"compositeMyCall"] = [NSString stringWithFormat:@"%@/%@", [header[@"myCall"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]], [header[@"myCall2"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    
    if([header[@"direction"] isEqualToString:@"TX"]) {
        header[@"color"] = [NSColor redColor];
        header[@"message"] = [[NSUserDefaults standardUserDefaults] stringForKey:@"slowDataMessage"];
        self.statusLED.image = [NSImage imageNamed:@"Red LED"];
    } else {
        header[@"color"] = [NSColor colorWithCalibratedRed:0.088 green:0.373 blue:0.139 alpha:1.000];
        self.statusLED.image = [NSImage imageNamed:@"Green LED"];
    }
    
    NSNumber *streamId = header[@"streamId"];
    
    if(![self updateQsoId:streamId usingBlock:^(NSMutableDictionary *qso, NSUInteger qsoIndex) {}]) {
        if(self.mapPopover.isShown)
           ((BTRMapPopupController *)self.mapPopover.contentViewController).suppressClose = YES;

        [self.qsoList addObject:header];
        [self.heardTableController rearrangeObjects];
        
        BTRMainWindowViewController __weak *weakSelf = self;
        self.qsoTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(self.qsoTimer, dispatch_time(DISPATCH_TIME_NOW, 100ull * NSEC_PER_MSEC), 100ull * NSEC_PER_MSEC, 10ull * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(self.qsoTimer, ^{
            [weakSelf updateQsoId:streamId usingBlock:^(NSMutableDictionary *qso, NSUInteger qsoIndex) {
                qso[@"duration"] = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSinceDate:qso[@"time"]]];
            }];
        });
        dispatch_resume(self.qsoTimer);
    }
}

-(void)streamDidEnd:(NSNumber *)streamId atTime:(NSDate *)time {
    dispatch_source_cancel(self.qsoTimer);
    
    [self updateQsoId:streamId usingBlock:^(NSMutableDictionary *qso, NSUInteger qsoIndex) {
        NSDate *headerTime = time;
        qso[@"duration"] = [NSNumber numberWithDouble:[headerTime timeIntervalSinceDate:qso[@"time"]]];
        if([qso[@"direction"] isEqualToString:@"TX"])
            qso[@"color"] = [NSColor colorWithCalibratedRed:1.0 green:0.0 blue:0.0 alpha:0.5];
        else
            qso[@"color"] = [NSColor blackColor];
    }];
    
    NSUInteger qsoIndex = [BTRMainWindowViewController findQsoId:streamId inArray:self.heardTableController.arrangedObjects];
    
    //  If we can't find the QSO, it's probably not visible and we don't need to reset its color.
    if(qsoIndex != NSNotFound)
        [self resetColorForRowView:[self.heardTableView rowViewAtRow:qsoIndex makeIfNecessary:NO] atRow:qsoIndex];

    self.statusLED.image = [NSImage imageNamed:@"Gray LED"];
}

-(void)slowDataReceived:(NSString *)slowData forStreamId:(NSNumber *)streamId {
    [self updateQsoId:streamId usingBlock:^(NSMutableDictionary *qso, NSUInteger qsoIndex) {
        qso[@"message"] = slowData;
    }];
}

-(void)locationReceived:(BTRAprsLocation *)location forStreamId:(NSNumber *)streamId {
    NSParameterAssert(location != nil);
    
    [self updateQsoId:streamId usingBlock:^(NSMutableDictionary *qso, NSUInteger qsoIndex) {
        CLLocation *oldLocation = ((BTRAprsLocation *)qso[@"location"]).location;
        qso[@"location"] = location;

        if(oldLocation && [location.location distanceFromLocation:oldLocation] < 100.0)
            return;

        qso[@"city"] = @"Searching city database…";
        [self.geocoder reverseGeocodeLocation:location.location completionHandler:^(NSArray <CLPlacemark *> *placemarks, NSError *error) {
            if(!placemarks) {
                NSLog(@"placemarks are nil");
                return;
            }
            if(error) {
                NSLog(@"Error returned from geocoder: %@", error);
                return;
            }
            if(placemarks.count == 0) {
                NSLog(@"No placemarks returned");
                return;
            }
            
            //NSLog(@"Got %ld placemarks", placemarks.count);
            //NSLog(@"Got placemarks: %@", [NSString stringWithFormat:@"%@, %@, %@", placemarks[0].locality, placemarks[0].administrativeArea, placemarks[0].country]);
            [self updateQsoId:streamId usingBlock:^(NSMutableDictionary *innerQso, NSUInteger innerQsoIndex) {
                    innerQso[@"city"] = [NSString stringWithFormat:@"%@, %@, %@", placemarks[0].locality, placemarks[0].administrativeArea, placemarks[0].country];
            }];
            // qso[@"city"] = [NSString stringWithFormat:@"%@, %@, %@", placemarks[0].locality, placemarks[0].administrativeArea, placemarks[0].country];
        }];
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.qsoList = [[NSMutableArray alloc] init];
    
    self.mapPopover = [[NSPopover alloc] init];
    self.mapPopover.contentViewController = [[BTRMapPopupController alloc] initWithNibName:nil bundle:nil];
    self.mapPopover.behavior = NSPopoverBehaviorTransient;
    self.mapPopover.delegate = (BTRMapPopupController *) self.mapPopover.contentViewController;
    
    self.addPopover = [[NSPopover alloc] init];
    BTRAddPopupController *addController = [[BTRAddPopupController alloc] initWithNibName:nil bundle:nil];
    addController.reflectorArrayController = self.reflectorTableController;
    self.addPopover.contentViewController = addController;
    self.addPopover.behavior = NSPopoverBehaviorSemitransient;
    self.addPopover.delegate = addController;
    
    [self bind:@"txKeyCode" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.shortcutValue" options:@{NSValueTransformerNameBindingOption: MASDictionaryTransformerName}];
    
    [self.view.window makeFirstResponder:self.view];
    self.view.window.initialFirstResponder = self.view;
    
    [BTRDataEngine sharedInstance].delegate = self;
    
    [self.reflectorTableView registerForDraggedTypes:@[ @"net.nh6z.Dummy.reflector" ]];
    self.reflectorTableView.dataSource = self;
    
    self.heardTableView.delegate = self;
    self.heardTableController.sortDescriptors = @[ [[NSSortDescriptor alloc] initWithKey:@"time" ascending:NO] ];
    
    [self.txButton setPeriodicDelay:.1f interval:.1f];
    self.txButtonState = NSOffState;
    
    self.speechSynth = [[NSSpeechSynthesizer alloc] initWithVoice:@"com.apple.speech.synthesis.voice.samantha"];
    if(self.speechSynth == nil) {
        NSLog(@"Could not initialize speech synthesizer.");
    }
    self.geocoder = [[CLGeocoder alloc] init];
    NSAssert(self.geocoder != nil, @"Geocoder did not initialize");
    
    self.volumeSlider.floatValue = [[NSUserDefaults standardUserDefaults] floatForKey:@"outputVolume"];
}

-(void)destinationDidLink:(NSString *)destination {
    self.repeaterInfo.stringValue = [NSString stringWithFormat:@"Linked to %@", destination];

    if([[NSUserDefaults standardUserDefaults] boolForKey:@"voiceAnnounceOnStatusChange"])
        [self.speechSynth startSpeakingString:[[NSString stringWithFormat:@"Linked to [[char LTRL]] %@ [[char NORM]]", destination] lowercaseString]];
    
    NSDockTile *dockTile = [NSApplication sharedApplication].dockTile;
    dockTile.badgeLabel = destination;
    [dockTile display];
    
    self.txButton.enabled = YES;
    
    [self.reflectorTableView enumerateAvailableRowViewsUsingBlock:^void(NSTableRowView *rowView, NSInteger row) {
        NSTextField *reflectorView = ((NSTableCellView *)[rowView viewAtColumn:0]).textField;
        if([reflectorView.objectValue isEqualToString:destination])
            reflectorView.textColor = [NSColor redColor];
    }];
}

-(void)destinationDidUnlink:(NSString *)destination {
    self.repeaterInfo.stringValue = @"Unlinked";
    
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"voiceAnnounceOnStatusChange"])
        [self.speechSynth startSpeakingString:self.repeaterInfo.stringValue];
    
    NSDockTile *dockTile = [NSApplication sharedApplication].dockTile;
    dockTile.badgeLabel = nil;
    [dockTile display];
    
    self.txButton.enabled = NO;
    
    [self.reflectorTableView enumerateAvailableRowViewsUsingBlock:^void(NSTableRowView *rowView, NSInteger row) {
        NSTextField *reflectorView = ((NSTableCellView *)[rowView viewAtColumn:0]).textField;
        if([reflectorView.objectValue isEqualToString:destination])
            reflectorView.textColor = [NSColor blackColor];
    }];
}

-(void)destinationDidError:(NSString *)destination error:(NSError *)error {
    NSAlert *alert = [NSAlert alertWithError:error];
    dispatch_async(dispatch_get_main_queue(), ^{
        [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response){}];
    });
}

-(void)destinationWillLink:(NSString *)destination {
    self.repeaterInfo.stringValue = [NSString stringWithFormat:@"Linking to %@", destination];
}
-(void)destinationDidConnect:(NSString *)destination {
    self.repeaterInfo.stringValue = [NSString stringWithFormat:@"Connected to %@. Attempting to establish link.", destination];
}


- (IBAction)doHeardDoubleClick:(id)sender {
    NSLog(@"Got double click, row %ld column %ld", self.heardTableView.clickedRow, self.heardTableView.clickedColumn);
    if(self.heardTableView.clickedRow < 0)
        return;
    
    NSDictionary *qso = self.heardTableController.arrangedObjects[self.heardTableView.clickedRow];
    
    if(qso[@"location"]) {
        BTRAprsLocation *location = qso[@"location"];
        if(!location.callsign)
            location.callsign = qso[@"myCall"];

        ((BTRMapPopupController *)self.mapPopover.contentViewController).annotation = qso[@"location"];
        ((BTRMapPopupController *)self.mapPopover.contentViewController).qsoId = qso[@"streamId"];
        NSView *clickedView = [self.heardTableView viewAtColumn:[self.heardTableView columnWithIdentifier:@"Location"] row:self.heardTableView.clickedRow makeIfNecessary:NO];
        [self.mapPopover showRelativeToRect:NSMakeRect(0, 0, 300, 300) ofView:clickedView preferredEdge:NSRectEdgeMaxY];
    }
}

-(IBAction)doReflectorDoubleClick:(id)sender {
    if(self.reflectorTableController.selectedObjects.count != 1) {
        NSBeep();
        return;
    }
    
    NSString *reflector = self.reflectorTableController.selectedObjects[0][@"reflector"];
    
    if(reflector.length < 8)
        return;

    if([reflector isEqualToString:[BTRDataEngine sharedInstance].network.linkTarget]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [[BTRDataEngine sharedInstance] unlink];
        });
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [[BTRDataEngine sharedInstance] linkTo:reflector];
        });
    }
    
    [self.reflectorTableView deselectAll:self];
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
    
    [self.reflectorTableView deselectAll:self];
}

- (IBAction)doUnlink:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [[BTRDataEngine sharedInstance] unlink];
    });
    
    [self.reflectorTableView deselectAll:self];
}

- (IBAction)doVolumeChange:(id)sender {
    [BTRDataEngine sharedInstance].audio.outputVolume = self.volumeSlider.floatValue;
    [[NSUserDefaults standardUserDefaults] setFloat:self.volumeSlider.floatValue forKey:@"outputVolume"];
}


-(void) addReflector:(id)sender {
    [self.addPopover showRelativeToRect:NSMakeRect(0, 0, 300, 300) ofView:sender preferredEdge:NSRectEdgeMaxY];
}

-(void)startTx {
    if(![BTRDataEngine sharedInstance].network) {
        NSBeep();
        return;
    }
    [self.view.window makeFirstResponder:self.view];
    
    [BTRDataEngine sharedInstance].audio.xmit = YES;    
}

-(void)endTx {
    [BTRDataEngine sharedInstance].audio.xmit = NO;
    self.statusLED.image = [NSImage imageNamed:@"Gray LED"];
}

- (IBAction)doTx:(id)sender {    
    if(self.txButton.state == self.txButtonState)
        [self startTx];
    else
        [self endTx];
    
    self.txButtonState = self.txButton.state;
}

#pragma mark - Text Editing Control

-(BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL result = [control.window makeFirstResponder:self.view];
        if(result == NO)
            NSLog(@"Would not resign first responder");
    });
    return YES;
}


#pragma mark - Reflector Drag and Drop support

- (id <NSPasteboardWriting>) tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    if(tableView != self.reflectorTableView)
        return nil;

    NSDictionary *reflector = self.reflectorTableController.arrangedObjects[row];
    
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setPropertyList:reflector forType:@"net.nh6z.Dummy.reflector"];
    
    return item;
}

-(NSDragOperation) tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    if(tableView != self.reflectorTableView)
        return NO;

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

#pragma mark - Heard List QSO Coloring

-(void)resetColorForRowView:(NSTableRowView *)rowView atRow:(NSUInteger)row {
    for(int i = 0; i < rowView.numberOfColumns; ++i)
        ((NSTableCellView *)[rowView viewAtColumn:i]).textField.textColor = self.heardTableController.arrangedObjects[row][@"color"];
}

-(void)tableView:(NSTableView *)tableView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
    if(tableView != self.heardTableView)
        return;

    [self resetColorForRowView:rowView atRow:row];
    
    if(self.mapPopover.isShown) {
        NSUInteger popoverRow = [BTRMainWindowViewController findQsoId:((BTRMapPopupController *)self.mapPopover.contentViewController).qsoId inArray:self.heardTableController.arrangedObjects];
        
        NSAssert(popoverRow != NSNotFound, @"QSO ID %ld not found in popover relocation", popoverRow);
        
        NSView *popoverAnchorView = [self.heardTableView viewAtColumn:[self.heardTableView columnWithIdentifier:@"Location"] row:popoverRow makeIfNecessary:NO];
        if(popoverAnchorView && popoverRow == row) {
            [self.mapPopover showRelativeToRect:NSMakeRect(0, 0, 300, 300) ofView:popoverAnchorView preferredEdge:NSRectEdgeMaxY];
            ((BTRMapPopupController *)self.mapPopover.contentViewController).suppressClose = NO;
        }

    }
}

#pragma mark - Heard List Selection Control

- (NSIndexSet *) tableView:(NSTableView *)tableView selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes {
    if(tableView == self.heardTableView)
        return nil;
    
    return proposedSelectionIndexes;
}

-(void)keyDown:(NSEvent *)theEvent {
    if(theEvent.keyCode == self.txKeyCode.keyCode &&
       ![self.view.window.firstResponder isKindOfClass:[NSTextView class]])
        if(!theEvent.isARepeat)
            [self startTx];
}

-(void)keyUp:(NSEvent *)theEvent {
    if(theEvent.keyCode == self.txKeyCode.keyCode &&
       ![self.view.window.firstResponder isKindOfClass:[NSTextView class]])
        if(!theEvent.isARepeat)
            [self endTx];
}
@end

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

#import "BTRAppDelegate.h"
#import "MASShortcut.h"
#import "BTRDataEngine.h"
#import "BTRSlowDataCoder.h"
#import "BTRAudioHandler.h"

@interface BTRMainWindowViewController ()

@property (nonatomic) dispatch_source_t qsoTimer;
@property (nonatomic) NSInteger txButtonState;
@property (nonatomic) NSSpeechSynthesizer *speechSynth;
@property (nonatomic) CLGeocoder *geocoder;

@end

@implementation BTRMainWindowViewController

-(BOOL)updateQsoId:(NSNumber *)streamId usingBlock:(void(^)(NSMutableDictionary *, NSUInteger))block {
    NSPredicate *currentFilterPredicate = self.heardTableController.filterPredicate;
    self.heardTableController.filterPredicate = nil;
    
    NSUInteger qsoIndex = [self.heardTableController.arrangedObjects indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        NSDictionary *entry = (NSDictionary *) obj;
        if([((NSNumber *)entry[@"streamId"]) isEqualToNumber:streamId]) {
            *stop = YES;
            return YES;
        }
        
        return NO;
    }];
    
    if(qsoIndex == NSNotFound)
        return NO;
    
    NSDictionary *qso = self.heardTableController.arrangedObjects[qsoIndex];
    NSMutableDictionary *newQso = [NSMutableDictionary dictionaryWithDictionary:qso];
    block(newQso, qsoIndex);
    
    [self.heardTableController removeObject:qso];
    [self.heardTableController addObject:newQso];
    
    self.heardTableController.filterPredicate = currentFilterPredicate;
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
        [self.heardTableController addObject:header];

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
        
        self.statusLED.image = [NSImage imageNamed:@"Gray LED"];
}

-(void)slowDataReceived:(NSString *)slowData forStreamId:(NSNumber *)streamId {
    [self updateQsoId:streamId usingBlock:^(NSMutableDictionary *qso, NSUInteger qsoIndex) {
        qso[@"message"] = slowData;
    }];
}

-(void)locationReceived:(CLLocation *)location forStreamId:(NSNumber *)streamId {
    [self updateQsoId:streamId usingBlock:^(NSMutableDictionary *qso, NSUInteger qsoIndex) {
        qso[@"location"] = location;
        qso[@"city"] = @"Searching city database…";
        [self.geocoder reverseGeocodeLocation:location completionHandler:^(NSArray <CLPlacemark *> *placemarks, NSError *error) {
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
    
    [self.view.window makeFirstResponder:self.view];
    self.view.window.initialFirstResponder = self.view;
    
    [BTRDataEngine sharedInstance].delegate = self;
    
    [self.reflectorTableView registerForDraggedTypes:@[ @"net.nh6z.Dummy.reflector" ]];
    self.reflectorTableView.dataSource = self;
    
    self.heardTableView.delegate = self;
    self.heardTableController.sortDescriptors = @[ [[NSSortDescriptor alloc] initWithKey:@"time" ascending:NO] ];
    
    [self.txButton setPeriodicDelay:.1f interval:.1f];
    self.txButtonState = NSOffState;
    
    self.speechSynth = [[NSSpeechSynthesizer alloc] initWithVoice:@"com.apple.speech.synthesis.voice.Vicki"];
    self.geocoder = [[CLGeocoder alloc] init];
}

-(void)destinationDidLink:(NSString *)destination {
    self.repeaterInfo.stringValue = [NSString stringWithFormat:@"Linked to %@", destination];
    [self.speechSynth startSpeakingString:self.repeaterInfo.stringValue];
    
    NSDockTile *dockTile = [NSApplication sharedApplication].dockTile;
    dockTile.badgeLabel = destination;
    [dockTile display];
    
    self.txButton.enabled = YES;
}

-(void)destinationDidUnlink:(NSString *)destination {
    self.repeaterInfo.stringValue = @"Unlinked";
    [self.speechSynth startSpeakingString:self.repeaterInfo.stringValue];
    
    NSDockTile *dockTile = [NSApplication sharedApplication].dockTile;
    dockTile.badgeLabel = nil;
    [dockTile display];
    
    self.txButton.enabled = NO;
}

-(void)destinationDidError:(NSString *)destination error:(NSError *)error {
    NSAlert *alert = [NSAlert alertWithError:error];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response){}];
}

-(void)destinationWillLink:(NSString *)destination {
    self.repeaterInfo.stringValue = [NSString stringWithFormat:@"Linking to %@", destination];
}
-(void)destinationDidConnect:(NSString *)destination {
    self.repeaterInfo.stringValue = [NSString stringWithFormat:@"Connected to %@. Attempting to establish link.", destination];
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

#pragma mark - Heard List QSO Coloring

-(void)tableView:(NSTableView *)tableView willDisplayCell:(id)cellObj forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if(tableView != self.heardTableView)
        return;
    
    NSTextFieldCell *cell = cellObj;
    
    NSDictionary *entry = self.heardTableController.arrangedObjects[row];
    
    cell.textColor = entry[@"color"];
}

-(void)keyDown:(NSEvent *)theEvent {
    BTRAppDelegate *delegate = [NSApp delegate];
    
    if(theEvent.keyCode == delegate.txKeyCode.keyCode &&
       ![self.view.window.firstResponder isKindOfClass:[NSTextView class]])
        if(!theEvent.isARepeat)
            [self startTx];
}

-(void)keyUp:(NSEvent *)theEvent {
    BTRAppDelegate *delegate = [NSApp delegate];

    if(theEvent.keyCode == delegate.txKeyCode.keyCode &&
       ![self.view.window.firstResponder isKindOfClass:[NSTextView class]])
        if(!theEvent.isARepeat)
            [self endTx];
}
@end

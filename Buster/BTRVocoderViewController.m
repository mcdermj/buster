//
//  BTRVocoderViewController.m
//
// Copyright (c) 2010-2015 - Jeremy C. McDermond (NH6Z)

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

#import "BTRVocoderViewController.h"

#import "BTRDataEngine.h"

@interface BTRVocoderViewController ()

@property (nonatomic, assign) NSViewController *configurationViewController;

-(void)replaceConfigurationViewControllerWith:(NSViewController *)viewController;

@end

@implementation BTRVocoderViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.vocoderType removeAllItems];
    for(Class driver in [BTRDataEngine vocoderDrivers]) {
        [self.vocoderType addItemWithTitle:[driver driverName]];
        NSMenuItem *addedItem = [self.vocoderType itemWithTitle:[driver driverName]];
        addedItem.representedObject = driver;
        if([[[[BTRDataEngine sharedInstance].vocoder class] driverName] isEqualToString:[driver driverName]])
            [self.vocoderType selectItem:addedItem];
    }
    
    [self replaceConfigurationViewControllerWith:[[BTRDataEngine sharedInstance].vocoder configurationViewController]];
}

-(void)replaceConfigurationViewControllerWith:(NSViewController *)viewController {
    if(self.configurationViewController)
        [self removeChildViewControllerAtIndex:[self.childViewControllers indexOfObject:self.configurationViewController]];
    [self addChildViewController:viewController];
    self.configurationViewController = viewController;
    
    viewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    viewController.view.identifier = @"Configuration";
    for(NSView *view in self.view.subviews)
        if([view.identifier isEqualToString:@"Configuration"])
            [self.view replaceSubview:view with:viewController.view];
    
    NSDictionary *viewsDictionary = @{ @"vocoderType" : self.vocoderType,
                                       @"configuration" : self.configurationViewController.view };
    
    NSMutableArray *constraints = [NSMutableArray arrayWithArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[vocoderType]-[configuration]|"
                                                                                                         options:0
                                                                                                         metrics:nil
                                                                                                           views:viewsDictionary]];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"|[configuration]|"
                                                                             options:0
                                                                             metrics:nil
                                                                               views:viewsDictionary]];
    
    [self.view addConstraints:constraints];
    
    //[self.view updateConstraintsForSubtreeIfNeeded];
    //[self.view layoutSubtreeIfNeeded];
    
    /* NSLog(@"Containing View Constraints: %@", self.view.constraints);
    for(NSView *view in self.view.subviews) {
        NSLog(@"%@ Contraints: %@", view.identifier, view.constraints);
    } */
}

-(void)selectVocoder:(id)sender {
    Class driver = self.vocoderType.selectedItem.representedObject;
    id <BTRVocoderProtocol> newVocoder = [[driver alloc] init];
    
    NSLog(@"doing select vocoder");
    
    [self replaceConfigurationViewControllerWith:[newVocoder configurationViewController]];
    [self replaceCurrentVocoderWith:newVocoder];
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromClass(driver) forKey:@"VocoderDriver"];
 }

-(void) replaceCurrentVocoderWith:(id <BTRVocoderProtocol>)vocoder {
    NSObject <BTRVocoderProtocol> *oldVocoder = [BTRDataEngine sharedInstance].vocoder;
    
    [oldVocoder stop];
    [BTRDataEngine sharedInstance].vocoder = vocoder;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [vocoder start];
    });

    for(NSString *binding in [oldVocoder exposedBindings])
        [oldVocoder unbind:binding];
}

@end

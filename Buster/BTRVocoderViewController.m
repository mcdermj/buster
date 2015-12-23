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

#import "BTRVocoderViewController.h"

#import "BTRDataEngine.h"

@interface BTRVocoderViewController ()

@property (nonatomic) NSViewController *configurationViewController;

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
    id <BTRVocoderDriver> newVocoder = [[driver alloc] init];
    
    NSLog(@"doing select vocoder");
    
    [self replaceConfigurationViewControllerWith:[newVocoder configurationViewController]];
    [self replaceCurrentVocoderWith:newVocoder];
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromClass(driver) forKey:@"VocoderDriver"];
 }

-(void) replaceCurrentVocoderWith:(id <BTRVocoderDriver>)vocoder {
    NSObject <BTRVocoderDriver> *oldVocoder = [BTRDataEngine sharedInstance].vocoder;
    
    [oldVocoder stop];
    [BTRDataEngine sharedInstance].vocoder = vocoder;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [vocoder start];
    });

    for(NSString *binding in [oldVocoder exposedBindings])
        [oldVocoder unbind:binding];
}

@end

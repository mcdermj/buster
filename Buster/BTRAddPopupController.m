//
//  BTRAddPopupController.m
//  Buster
//
//  Created by Jeremy McDermond on 9/29/15.
//  Copyright © 2015 NH6Z. All rights reserved.
//

#import "BTRAddPopupController.h"

#import "BTRDataEngine.h"

@interface BTRAddPopupController ()

@property (nonatomic, getter=inAutoComplete) BOOL complete;
@property (nonatomic) NSRange lastCompleteRange;

@end

@implementation BTRAddPopupController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

- (IBAction)doAdd:(id)sender {
    NSString *linkTarget = [self.destinationField.stringValue stringByPaddingToLength:8 withString:@" " startingAtIndex:0];
    linkTarget = [linkTarget stringByReplacingCharactersInRange:NSMakeRange(7, 1) withString:self.moduleField.titleOfSelectedItem];
    
    NSLog(@"String is %@", linkTarget);
    [self.reflectorArrayController addObject:@{ @"reflector": linkTarget } ];
    
    self.destinationField.stringValue = @"";
    [self.moduleField selectItemWithTitle:@"A"];
}

-(NSArray<NSString *> *) control:(NSControl *)control textView:(nonnull NSTextView *)textView completions:(nonnull NSArray<NSString *> *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(nonnull NSInteger *)index {
    NSLog(@"In completion handler");
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF like[cd] %@", [[textView.string copy] stringByAppendingString:@"*"]];
    
    NSArray<NSString *> *destinations = [BTRDataEngine sharedInstance].linkDriverDestinations;
    NSArray<NSString *> *completionStrings = [destinations filteredArrayUsingPredicate:predicate];
    
    *index = -1;
    return completionStrings;
}

-(void)controlTextDidChange:(NSNotification *)obj {
    NSLog(@"Text changed: %@", ((NSTextView *)obj.userInfo[@"NSFieldEditor"]).string);

    if(self.inAutoComplete)
        return;
    
    self.complete = YES;
    [[[obj userInfo] objectForKey:@"NSFieldEditor"] complete:nil];
    self.complete = NO;
}

/* -(BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if(commandSelector == @selector(deleteBackward:)) {
        if(textView.string.length < 1)
            return NO;
        
        self.complete = YES;
        textView.string = [textView.string substringToIndex:textView.string.length - 1];
        self.complete = NO;
        return NO;
    }
    
    return NO;
} */
@end

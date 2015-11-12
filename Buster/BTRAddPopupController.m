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

@end

@implementation BTRAddPopupController

-(void)awakeFromNib {
    [self.moduleField removeAllItems];
    
    for(unichar i = 'A'; i <= 'Z'; ++i)
        [self.moduleField addItemWithTitle:[NSString stringWithCharacters:&i length:1]];
}

- (IBAction)doAdd:(id)sender {
    NSString *linkTarget = [self.destinationField.stringValue stringByPaddingToLength:8 withString:@" " startingAtIndex:0];
    linkTarget = [linkTarget stringByReplacingCharactersInRange:NSMakeRange(7, 1) withString:self.moduleField.titleOfSelectedItem];
    
    [self.reflectorArrayController addObject:@{ @"reflector": linkTarget } ];
    
    self.destinationField.stringValue = @"";
    [self.moduleField selectItemWithTitle:@"A"];
}

-(NSArray<NSString *> *) control:(NSControl *)control textView:(nonnull NSTextView *)textView completions:(nonnull NSArray<NSString *> *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(nonnull NSInteger *)index {
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF like[cd] %@", [[textView.string copy] stringByAppendingString:@"*"]];
    
    NSArray<NSString *> *completionStrings = [[BTRDataEngine sharedInstance].linkDriverDestinations filteredArrayUsingPredicate:predicate];
    completionStrings = [completionStrings sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    
    *index = -1;
    return completionStrings;
}

-(void)controlTextDidChange:(NSNotification *)obj {
    if(self.inAutoComplete)
        return;
    
    NSText *destination = [[obj userInfo] objectForKey:@"NSFieldEditor"];
    
    self.complete = YES;
    [destination complete:nil];
    self.complete = NO;
}

@end

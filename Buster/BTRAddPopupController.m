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

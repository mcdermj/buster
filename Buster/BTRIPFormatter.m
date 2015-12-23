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

#import "BTRIPFormatter.h"

@interface BTRIPFormatter () {
    NSCharacterSet *invalidChars;
}

@end

@implementation BTRIPFormatter

- (id) init {
    self = [super init];
    if(self) {
        invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."].invertedSet;
    }
    
    return self;
}

- (id) initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    return [self init];
}

- (BOOL) isPartialStringValid:(NSString *__autoreleasing *)partialStringPtr proposedSelectedRange:(NSRangePointer)proposedSelRangePtr originalString:(NSString *)origString originalSelectedRange:(NSRange)origSelRange errorDescription:(NSString *__autoreleasing *)error {
    
    NSString *proposedString = *partialStringPtr;
    if(proposedString.length > 15) {
        proposedSelRangePtr = &origSelRange;
        
        // XXX Make the static analyzer not complain
        (void)proposedSelRangePtr;
        return NO;
    }
    
    NSArray *components = [proposedString componentsSeparatedByCharactersInSet:invalidChars];
    if(components.count > 1) {
        *partialStringPtr = [NSString stringWithString:origString];
        proposedSelRangePtr->length = origSelRange.length;
        proposedSelRangePtr->location = origSelRange.location;
        return NO;
    }
    
    return YES;
}

- (NSString *) stringForObjectValue:(id)obj {
    return (NSString *) obj;
}

- (BOOL) getObjectValue:(out __autoreleasing id *)obj forString:(NSString *)string errorDescription:(out NSString *__autoreleasing *)error {
    NSHost *host = [NSHost hostWithAddress:string];
    if(host.address) {
        *obj = host.address;
        return YES;
    }
    
    return NO;
}

@end

//
//  BTRMessageFormatter.m
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


#import "BTRMessageFormatter.h"

@interface BTRMessageFormatter ()

@end

@implementation BTRMessageFormatter

- (BOOL) isPartialStringValid:(NSString *__autoreleasing *)partialStringPtr proposedSelectedRange:(NSRangePointer)proposedSelRangePtr originalString:(NSString *)origString originalSelectedRange:(NSRange)origSelRange errorDescription:(NSString *__autoreleasing *)error {
    
    if(strlen((*partialStringPtr).UTF8String) > 20) {
        proposedSelRangePtr = &origSelRange;
        
        // XXX Make the static analyzer not complain
        (void)proposedSelRangePtr;
        return NO;
    }
    
    return YES;
}

- (NSString *) stringForObjectValue:(id)obj {
    return (NSString *) obj;
}

- (BOOL) getObjectValue:(out __autoreleasing id *)obj forString:(NSString *)string errorDescription:(out NSString *__autoreleasing *)error {
    *obj = string;
    return YES;
}


@end

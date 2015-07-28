//
//  DMYSlowDataHandler.m
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

#import "DMYSlowDataHandler.h"

const char syncBytes[] = { 0x55, 0x2D, 0x16 };
const char scrambler[] = { 0x70, 0x4F, 0x93 };

const char SLOW_DATA_TYPE_MASK = 0xF0;
const char SLOW_DATA_SEQUENCE_MASK = 0x0F;
const char SLOW_DATA_TYPE_TEXT = 0x40;

#define UNSCRAMBLE(x)   for(int i = 0; i < 3; ++i) \
                            dataFrame[(x)][i] = ((char *)data)[i] ^ scrambler[i];

@interface DMYSlowDataHandler () {
    char dataFrame[2][3];
    BOOL isTop;
    NSMutableString *messageData;
}
@end

@implementation DMYSlowDataHandler

-(id) init {
    self = [super init];
    if(self) {
        isTop = YES;
        messageData = [NSMutableString stringWithString:@"                    "];
        NSLog("Length is %lu", (unsigned long)messageData.length);
    }
    return self;
}

-(void)addData:(void *)data {
    if(!memcmp(data, syncBytes, 3)) {
        // NSLog(@"Got sync");
        isTop = YES;
        return;
    }
    
    if(isTop) {
        NSLog(@"In Top");
        UNSCRAMBLE(0)
        isTop = NO;
        return;
    }
    
    UNSCRAMBLE(1);
    
    NSLog(@"In Bottom");
    
    if((dataFrame[0][0] & SLOW_DATA_TYPE_MASK) != SLOW_DATA_TYPE_TEXT) {
        // NSLog(@"Type is not slow data: 0x%02X", dataFrame[0][0]);
        isTop = YES;
        return;
    }
    
    
    
    char sequence = dataFrame[0][0] & SLOW_DATA_SEQUENCE_MASK;
    if(sequence > 3) {
        NSLog(@"Bad sequence 0x%02X", sequence);
        isTop = YES;
        return;
    }
    NSString *replacementString = [[NSString alloc] initWithBytes:((char*) dataFrame) + 1 length:5 encoding:NSUTF8StringEncoding];
    // [replacementString appendString:[[NSString alloc] initWithBytes:bottomHalf length:3 encoding:NSUTF8StringEncoding]];
    if(replacementString == nil) {
        NSLog(@"Something went wrong with the string!");
        isTop = YES;
        return;
    }
    NSLog(@"Replacing %@", replacementString);
    [messageData replaceCharactersInRange:NSMakeRange(sequence * 5, 5) withString:replacementString];
    NSLog(@"Message string is %@", messageData);
    
    if(sequence == 3) {
        //  Send the notification and reset messageData
        NSLog(@"We're done!");
    }

    isTop = YES;
}

@end

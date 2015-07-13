//
//  DMYDV3KVocoder.h
//  Dummy
//
//  Created by Jeremy McDermond on 7/12/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "DMYVocoderProtocol.h"

@interface DMYDV3KVocoder : NSObject <DMYVocoderProtocol>

- (id) initWithPort:(NSString *)serialPort;
- (void) decodeData:(NSData *) data;
- (BOOL) start;

@property NSString *serialPort;
@property NSString *productId;
@property NSString *version;

@end

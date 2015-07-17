//
//  DMYDV3KVocoder.h
//  Dummy
//
//  Created by Jeremy McDermond on 7/12/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "DMYVocoderProtocol.h"

#import "DMYAudioHandler.h"

@interface DMYDV3KVocoder : NSObject <DMYVocoderProtocol>

- (id) initWithPort:(NSString *)serialPort;
// - (void) decodeData:(void *) data;
- (BOOL) start;

@property NSString *serialPort;
@property NSString *productId;
@property NSString *version;
@property long speed;
@property BOOL beep;

@property DMYAudioHandler *audio;

@end

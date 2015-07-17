//
//  DMYVocoderProtocol.h
//  Dummy
//
//  Created by Jeremy McDermond on 7/11/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

@protocol DMYVocoderProtocol
- (void) decodeData:(void *) data lastPacket:(BOOL)last;
@end

//
//  DMYGatewayHandler.h
//  Dummy
//
//  Created by Jeremy McDermond on 7/10/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "DMYVocoderProtocol.h"

extern NSString * const DMYNetworkHeaderReceived;
extern NSString * const DMYNetworkStreamStart;
extern NSString * const DMYNetworkStreamEnd;

@interface DMYGatewayHandler : NSObject

@property NSString *remoteAddress;
@property NSUInteger remotePort;
@property NSUInteger localPort;

@property id <DMYVocoderProtocol> vocoder;

@property (readonly) NSString *urCall;
@property (readonly) NSString *myCall;
@property (readonly) NSString *rpt1Call;
@property (readonly) NSString *rpt2Call;
@property (readonly) NSString *myCall2;
@property NSString *xmitMyCall;
@property NSString *xmitUrCall;
@property NSString *xmitRepeater;

- (id) initWithRemoteAddress:(NSString *)remoteAddress remotePort:(NSUInteger)remotePort localPort:(NSUInteger)localPort;
- (BOOL) start;
- (void) linkTo:(NSString *)reflector;

@end

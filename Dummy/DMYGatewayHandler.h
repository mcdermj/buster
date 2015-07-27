//
//  DMYGatewayHandler.h
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

#import <Foundation/Foundation.h>

#import "DMYVocoderProtocol.h"

extern NSString * const DMYNetworkHeaderReceived;
extern NSString * const DMYNetworkStreamStart;
extern NSString * const DMYNetworkStreamEnd;

@interface DMYGatewayHandler : NSObject

@property (copy, nonatomic) NSString *gatewayAddr;
@property (assign, nonatomic) NSUInteger gatewayPort;
@property (assign, nonatomic) NSUInteger repeaterPort;

@property (assign, nonatomic) id <DMYVocoderProtocol> vocoder;

@property (nonatomic, readonly, copy) NSString *urCall;
@property (nonatomic, readonly, copy) NSString *myCall;
@property (nonatomic, readonly, copy) NSString *rpt1Call;
@property (nonatomic, readonly, copy) NSString *rpt2Call;
@property (nonatomic, readonly, copy) NSString *myCall2;
@property (nonatomic, readonly, assign) NSUInteger streamId;

@property (copy, nonatomic) NSString *xmitMyCall;
@property (copy, nonatomic) NSString *xmitUrCall;
@property (copy, nonatomic) NSString *xmitRpt1Call;
@property (copy, nonatomic) NSString *xmitRpt2Call;

@property (nonatomic, readonly, copy) NSString *localText;
@property (nonatomic, readonly, copy) NSString *reflectorText;

- (id) initWithRemoteAddress:(NSString *)gatewayAddr remotePort:(NSUInteger)remotePort localPort:(NSUInteger)localPort;
- (id) init;
- (BOOL) start;
- (void) stop;
- (void) linkTo:(NSString *)reflector;
- (void) unlink;
- (void) sendAMBE:(void *)data lastPacket:(BOOL)last;

@end

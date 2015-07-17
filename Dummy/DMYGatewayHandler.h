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

//
//  BTRGatewayHandler.h
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

@protocol BTRVocoderDriver;
@class BTRSlowDataCoder;

#pragma mark - Notification Constants
extern NSString * const BTRNetworkHeaderReceived;
extern NSString * const BTRNetworkStreamStart;
extern NSString * const BTRNetworkStreamEnd;
extern NSString * const BTRRepeaterInfoReceived;

@interface BTRGatewayHandler : NSObject

@property (copy, nonatomic) NSString *gatewayAddr;
@property (nonatomic) NSUInteger gatewayPort;
@property (nonatomic) NSUInteger repeaterPort;

@property (nonatomic) id <BTRVocoderDriver> vocoder;
@property (nonatomic, readonly) BTRSlowDataCoder *slowData;

@property (copy, nonatomic) NSString *xmitMyCall;
@property (copy, nonatomic) NSString *xmitMyCall2;
@property (copy, nonatomic) NSString *xmitUrCall;
@property (copy, nonatomic) NSString *xmitRpt1Call;
@property (copy, nonatomic) NSString *xmitRpt2Call;

- (id) init;
- (BOOL) start;
- (void) stop;
- (void) linkTo:(NSString *)reflector;
- (void) unlink;
- (void) sendAMBE:(void *)data lastPacket:(BOOL)last;

@end

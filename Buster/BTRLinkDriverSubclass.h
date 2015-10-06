//
//  BTRLinkDriverSubclass.h
//  Buster
//
//  Created by Jeremy McDermond on 8/18/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "BTRLinkDriver.h"

#import "DStarUtils.h"

@interface BTRNetworkTimer : NSObject
@property (nonatomic) dispatch_source_t timerSource;
@property (nonatomic) CFAbsoluteTime lastEventTime;

-(id)initWithTimeout:(CFAbsoluteTime)timeout failureHandler:(void(^)())failureHandler;
-(void)ping;
@end

@interface BTRLinkDriver ()

//
//  Methods for the subclass to override
//
-(void)processPacket:(NSData *)packet;
-(NSString *)getAddressForReflector:(NSString *)reflector;
-(void)sendPoll;
-(void)sendUnlink;
-(void)sendLink;
-(void)sendFrame:(struct dstar_frame *)frame;

//
//  Pass off the D-STAR frame data to the rest of the system.
//  This needs to be called when we receive a D-STAR frame from the reflector.
//
-(void)processFrame:(struct dstar_frame *)frame;

//
//  Send a packet to the reflector.  This is an NSData so we know the length of the packet.
//
-(void)sendPacket:(NSData *)packet;

// -(void)unlink;

-(void)terminateCurrentStream;

//
//  Override these to set the parameters in the subclass.
//
@property (nonatomic, readonly) CFAbsoluteTime pollInterval;
@property (nonatomic, readonly) unsigned short clientPort;
@property (nonatomic, readonly) unsigned short serverPort;
@property (nonatomic, readonly) size_t packetSize;
@property (nonatomic, readonly) BOOL hasReliableChecksum;

//
//  Properties subclasses might need.  You should take care of making sure linkState is correct.
//
@property (nonatomic, readwrite) enum linkState linkState;
@property (nonatomic, readonly, copy) NSString *rpt1Call;
@property (nonatomic) unsigned short rxStreamId;
@property (nonatomic) BTRNetworkTimer *qsoTimer;
@property (nonatomic) char rxSequence;
@end

//
//  Utilities to create callsign strings to fill packets.
//
@interface NSString (BTRCallsignUtils)
@property (nonatomic, readonly) NSString *paddedCall;
@property (nonatomic, readonly) NSString *callWithoutModule;
@property (nonatomic, readonly) NSString *paddedShortCall;

+(NSString *)stringWithCallsign:(void *)callsign;
+(NSString *)stringWithShortCallsign:(void *)callsign;

@end
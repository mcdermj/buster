//
//  BTRLinkDriverSubclass.h
//  Buster
//
//  Created by Jeremy McDermond on 8/18/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "BTRLinkDriver.h"

#define call_to_nsstring(a) [[NSString alloc] initWithBytes:(a) length:sizeof((a)) encoding:NSUTF8StringEncoding]

NS_INLINE BOOL isSequenceAhead(uint8 incoming, uint8 counter, uint8 max) {
    uint8 halfmax = max / 2;
    
    if(counter < halfmax) {
        if(incoming <= counter + halfmax) return YES;
    } else {
        if(incoming > counter ||
           incoming <= counter - halfmax) return YES;
    }
    
    return NO;
}

@interface BTRLinkDriver ()

-(id)initWithPort:(short)port packetSize:(size_t)packetSize;
-(void)processPacket:(void *)packet;
-(void)sendPacket:(NSData *)packet;
-(NSString *)getAddressForReflector:(NSString *)reflector;
-(void)sendPoll;
-(void)sendUnlink;
-(void)sendLink;
-(void)terminateCurrentStream;
- (uint16) calculateChecksum:(void *)data length:(size_t)length;

//  XXX A bunch of this stuff can move when we're done.
@property (nonatomic, readwrite) enum linkState linkState;
@property (nonatomic, readwrite, copy) NSString * linkTarget;
@property (nonatomic) int socket;
@property (nonatomic) dispatch_source_t dispatchSource;
@property (nonatomic) dispatch_source_t watchdogTimerSource;
@property (nonatomic) dispatch_source_t pollTimerSource;
@property (nonatomic) dispatch_source_t linkWatchdogTimerSource;
@property (nonatomic) dispatch_queue_t writeQueue;
@property (nonatomic) unsigned short rxStreamId;
@property (nonatomic) unsigned short txStreamId;
@property (nonatomic) char rxSequence;
@property (nonatomic) char txSequence;
@property (nonatomic) CFAbsoluteTime lastPacketTime;
@property (nonatomic) CFAbsoluteTime lastLinkPacketTime;

@end
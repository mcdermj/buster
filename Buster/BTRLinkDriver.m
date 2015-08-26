//
//  BTRLinkDriver.m
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

#import "BTRLinkDriver.h"
#import "BTRLinkDriverSubclass.h"
#import "BTRLinkDriverProtocol.h"
#import "BTRDataEngine.h"
#import "BTRSlowDataCoder.h"

#import <arpa/inet.h>
#import <sys/ioctl.h>

@implementation NSString (BTRCallsignUtils)
-(NSString *)paddedCall {
    return [self stringByPaddingToLength:8 withString:@" " startingAtIndex:0];
}

-(NSString *)paddedShortCall {
    return [self stringByPaddingToLength:4 withString:@" " startingAtIndex:0];
}

-(NSString *)callWithoutModule {
    return [[self substringWithRange:NSMakeRange(0, 7)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

+(NSString *)stringWithCallsign:(void *)callsign {
    return [[[NSString alloc] initWithBytes:callsign length:8 encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

+(NSString *)stringWithShortCallsign:(void *)callsign {
    return [[[NSString alloc] initWithBytes:callsign length:4 encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@end

@interface BTRNetworkTimer : NSObject
@property (nonatomic) dispatch_source_t timerSource;
@property (nonatomic) CFAbsoluteTime lastEventTime;

-(id)initWithTimeout:(CFAbsoluteTime)timeout failureHandler:(void(^)())failureHandler;
-(void)ping;
@end

@implementation BTRNetworkTimer

-(id)initWithTimeout:(CFAbsoluteTime)timeout failureHandler:(void(^)())failureHandler {
    self = [super init];
    if(self) {
        _lastEventTime = CFAbsoluteTimeGetCurrent() + (3600.0 * 24.0 * 365.0);
        _timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        unsigned long long period = (unsigned long long) ((timeout / 10) * NSEC_PER_SEC);
        dispatch_source_set_timer(_timerSource, dispatch_time(DISPATCH_TIME_NOW, 0), period, period / 10);
        BTRNetworkTimer __weak *weakSelf = self;
        dispatch_source_set_event_handler(_timerSource, ^{
            if(CFAbsoluteTimeGetCurrent() > weakSelf.lastEventTime + timeout) {
                NSLog(@"Timer expired after %f seconds", CFAbsoluteTimeGetCurrent() - weakSelf.lastEventTime);
                failureHandler();
            }
        });
        dispatch_resume(_timerSource);
    }
    
    return self;
}

-(void) dealloc {
    dispatch_source_cancel(self.timerSource);
}

-(void) ping {
    self.lastEventTime = CFAbsoluteTimeGetCurrent();
}
@end

@interface BTRLinkDriver ()

@property (nonatomic) BTRNetworkTimer *linkTimer;
@property (nonatomic) BTRNetworkTimer *qsoTimer;
@property (nonatomic) int socket;
@property (nonatomic) dispatch_source_t dispatchSource;
@property (nonatomic) dispatch_source_t pollTimerSource;
@property (nonatomic) dispatch_queue_t writeQueue;
@property (nonatomic) unsigned short rxStreamId;
@property (nonatomic) char rxSequence;
@property (nonatomic) unsigned short txStreamId;
@property (nonatomic) char txSequence;
@property (nonatomic, readwrite, copy) NSString * linkTarget;
@property (nonatomic) CFAbsoluteTime connectTime;

-(void)terminateCurrentStream;

@end

@implementation BTRLinkDriver

@synthesize vocoder = _vocoder;
@synthesize myCall = _myCall;
@synthesize myCall2 = _myCall2;
@synthesize delegate = _delegate;

+(BOOL)canHandleLinkTo:(NSString *)reflector {
    return NO;
}

-(id)initWithLinkTo:(NSString *)linkTarget {
    self = [super init];
    if(self) {
        _linkTarget = @"";
        _linkState = UNLINKED;
        _rxStreamId = 0;
        _txStreamId = (short) random();
        _vocoder = nil;
        _rxSequence = 0;
        _txSequence = 0;
        
        self.linkTarget = [linkTarget copy];
        BTRLinkDriver __weak *weakSelf = self;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [weakSelf connect];
        });
    }
    
    return self;
}

-(void)connect {
    dispatch_queue_attr_t dispatchQueueAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
    _writeQueue = dispatch_queue_create("net.nh6z.Buster.LinkWrite", dispatchQueueAttr);
    
    _socket = socket(PF_INET, SOCK_DGRAM, 0);
    if(_socket == -1) {
        NSLog(@"Error opening socket: %s\n", strerror(errno));
        return;
    }
    
    int one = 1;
    if(setsockopt(_socket, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one))) {
        NSLog(@"Couldn't set socket to SO_REUSEADDR: %s\n", strerror(errno));
        return;
    }
    
    if(fcntl(_socket, F_SETFL, O_NONBLOCK) == -1) {
        NSLog(@"Couldn't set socket to nonblocking: %s\n", strerror(errno));
        return;
    }
    
    struct sockaddr_in clientAddr = {
        .sin_len = sizeof(struct sockaddr_in),
        .sin_family = AF_INET,
        .sin_port = htons(self.clientPort),
        .sin_addr.s_addr = INADDR_ANY
    };
    
    if(bind(_socket, (const struct sockaddr *) &clientAddr, (socklen_t) sizeof(clientAddr))) {
        NSLog(@"Couldn't bind gateway socket: %s\n", strerror(errno));
        return;
    }
    
    _dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) _socket, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    BTRLinkDriver __weak *weakSelf = self;
    dispatch_source_set_event_handler(_dispatchSource, ^{
        void *incomingPacket = malloc(weakSelf.packetSize);
        size_t bytesRead;
        
        do {
            bytesRead = recv(weakSelf.socket, incomingPacket, self.packetSize, 0);
            if(bytesRead == -1) {
                if(errno == EAGAIN)
                    break;
                NSLog(@"Couldn't read DPlus packet: %s", strerror(errno));
                free(incomingPacket);
                return;
            }
            
            [weakSelf.linkTimer ping];
            
            [weakSelf processPacket:[NSData dataWithBytes:incomingPacket length:bytesRead]];
        } while(bytesRead > 0);
        free(incomingPacket);
    });
    
    dispatch_resume(_dispatchSource);
    
    NSDictionary *infoDict = @{ @"local": [NSString stringWithFormat:@"Linking to %@", self.linkTarget],
                                @"reflector": self.linkTarget,
                                @"status": @"" };
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:weakSelf userInfo:infoDict];
    });
    
    NSString *reflectorAddress = [self getAddressForReflector:(NSString *)[[self.linkTarget substringWithRange:NSMakeRange(0, 7)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    if(!reflectorAddress) {
        infoDict = @{ @"local": [NSString stringWithFormat:@"Couldn't find %@", self.linkTarget],
                      @"reflector": self.linkTarget,
                      @"status": @"" };
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:weakSelf userInfo:infoDict];
        });
        
        NSLog(@"Couldn't find reflector %@", self.linkTarget);
        return;
    }
    
    struct sockaddr_in serverAddr = {
        .sin_len = sizeof(struct sockaddr_in),
        .sin_family = AF_INET,
        .sin_port = htons(self.serverPort),
        .sin_addr.s_addr = inet_addr([reflectorAddress cStringUsingEncoding:NSUTF8StringEncoding])
    };
    
    NSLog(@"Linking to %@ at %@", self.linkTarget, reflectorAddress);
    
    if(connect(self.socket, (const struct sockaddr *) &serverAddr, (socklen_t) sizeof(serverAddr))) {
        NSLog(@"Couldn't connect socket: %s\n", strerror(errno));
        return;
    }
    
    NSLog(@"Link Connection Complete");
    
    self.linkState = CONNECTED;
    
    dispatch_source_t retrySource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    dispatch_source_set_timer(retrySource, dispatch_time(DISPATCH_TIME_NOW, 0), 500ull * NSEC_PER_MSEC, 1ull * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(retrySource, ^{
        if(weakSelf.linkState != CONNECTED || CFAbsoluteTimeGetCurrent() > weakSelf.connectTime + 10.0) {
            dispatch_source_cancel(retrySource);
            return;
        }
        
        [weakSelf sendLink];
    });
    self.connectTime = CFAbsoluteTimeGetCurrent();
    dispatch_resume(retrySource);
}

- (void) dealloc  {
    NSLog(@"Calling dealloc");
    //[self unlink];
    // XXX This should be on the cancel handler.
    close(self.socket);
}

-(void)startPoll {
    BTRLinkDriver __weak *weakSelf = self;
    
    self.pollTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    dispatch_source_set_timer(self.pollTimerSource, dispatch_time(DISPATCH_TIME_NOW, 0), (unsigned long long)(self.pollInterval * NSEC_PER_SEC), (unsigned long long)(self.pollInterval * NSEC_PER_SEC) / 10);
    dispatch_source_set_event_handler(self.pollTimerSource, ^{
        [weakSelf sendPoll];
    });
    dispatch_resume(self.pollTimerSource);
}

-(void)stopPoll {
    dispatch_source_cancel(self.pollTimerSource);
    self.pollTimerSource = nil;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreturn-type"
-(void)processPacket:(NSData *)packet {
    [self doesNotRecognizeSelector:_cmd];
}
-(void)sendPoll {
    [self doesNotRecognizeSelector:_cmd];
}
-(void)sendUnlink {
    [self doesNotRecognizeSelector:_cmd];
}
-(void)sendLink {
    [self doesNotRecognizeSelector:_cmd];
}
-(void)sendFrame:(struct dstar_frame *)frame {
    [self doesNotRecognizeSelector:_cmd];
}
-(NSString *)getAddressForReflector:(NSString *)reflector {
    [self doesNotRecognizeSelector:_cmd];
}
-(CFAbsoluteTime)pollInterval {
    [self doesNotRecognizeSelector:_cmd];
}
-(unsigned short)clientPort {
    [self doesNotRecognizeSelector:_cmd];
}
-(unsigned short)serverPort {
    [self doesNotRecognizeSelector:_cmd];
}
-(size_t)packetSize {
    [self doesNotRecognizeSelector:_cmd];
}
-(BOOL)hasReliableChecksum {
    [self doesNotRecognizeSelector:_cmd];
}
#pragma clang diagnostic pop

-(void)setLinkState:(enum linkState)linkState {
    if(_linkState == linkState)
        return;

    switch(linkState) {
        case UNLINKED: {
            BTRLinkDriver __weak *weakSelf = self;
            NSDictionary *infoDict = @{ @"local": @"Unlinked",
                                        @"reflector": self.linkTarget,
                                        @"status": @"" };
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:weakSelf userInfo:infoDict];
            });
            
            [self stopPoll];
            self.linkTimer = nil;
            dispatch_source_cancel(self.dispatchSource);
            break;
        }
        case CONNECTED: {
            BTRLinkDriver __weak *weakSelf = self;
            NSDictionary *infoDict = @{ @"local": [NSString stringWithFormat:@"Connected to %@, waiting for link acknowledgment", self.linkTarget],
                                        @"reflector": self.linkTarget,
                                        @"status": @"" };
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:weakSelf userInfo:infoDict];
            });
            
            [self startPoll];
            
            self.linkTimer = [[BTRNetworkTimer alloc] initWithTimeout:30.0 failureHandler:^{
                [weakSelf unlink];
            }];
        }
        case LINKING: {
            
            break;
        }
        case LINKED: {
            BTRLinkDriver __weak *weakSelf = self;
            
            NSDictionary *infoDict = @{ @"local": [NSString stringWithFormat:@"Linked to %@", self.linkTarget],
                                        @"reflector": self.linkTarget,
                                        @"status": @"" };
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:weakSelf userInfo:infoDict];
            });
            if(_linkState == UNLINKED) {
                [self startPoll];
                self.linkTimer = [[BTRNetworkTimer alloc] initWithTimeout:30.0 failureHandler:^{
                    [weakSelf unlink];
                }];
            }
        }
    }
               
    _linkState = linkState;
}

-(void) terminateCurrentStream {
    /* NSDictionary *streamData = @{
                                 @"streamId": [NSNumber numberWithUnsignedInteger:self.rxStreamId],
                                 @"time": [NSDate date]
                                 }; */
    
    [self.delegate streamDidEnd:[NSNumber numberWithUnsignedInteger:self.rxStreamId] atTime:[NSDate date]];
    NSLog(@"Stream %d ends", self.rxStreamId);
    self.rxStreamId = 0;
    self.qsoTimer = nil;
}

-(void)unlink {
    if(self.linkState == UNLINKED)
        return;
    
    BTRLinkDriver __weak *weakSelf = self;
    int tries = 0;
    
    if(self.rxStreamId != 0)
        [self terminateCurrentStream];
    
    do {
        dispatch_sync(self.writeQueue, ^{
            [weakSelf sendUnlink];
        });
        usleep(USEC_PER_SEC / 10);  // XXX Don't like sleeping blindly here.
        if(tries++ > 10)
            break;
    } while(self.linkState != UNLINKED);
    
    self.linkTimer = nil;
    
    NSLog(@"Unlinked from %@", self.linkTarget);
    self.linkTarget = @"";
}

- (void) sendPacket:(NSData *)packet {
    BTRLinkDriver __weak *weakSelf = self;
    dispatch_async(self.writeQueue, ^{
        size_t bytesSent = send(weakSelf.socket, packet.bytes, packet.length, 0);
        if(bytesSent == -1) {
            NSLog(@"Couldn't write link request: %s", strerror(errno));
            return;
        }
        if(bytesSent != packet.length) {
            NSLog(@"Short write on link");
            return;
        }
    });
}

-(void)processFrame:(struct dstar_frame *)frame {
    BTRLinkDriver __weak *weakSelf = self;

    switch(frame->type) {
        case 0x10: {
            [self.qsoTimer ping];
            
            uint16 calculatedSum = dstar_calc_sum(&frame->header);
            if(self.hasReliableChecksum && frame->header.sum != 0xFFFF && frame->header.sum != calculatedSum) {
                NSLog(@"Header checksum mismatch: expected 0x%04hX calculated 0x%04hX", frame->header.sum, calculatedSum);
                return;
            }
            
            if(![self.linkTarget isEqualToString:[NSString stringWithCallsign:frame->header.rpt1Call]] &&
               ![self.linkTarget isEqualToString:[NSString stringWithCallsign:frame->header.rpt2Call]])
                return;
            
            if(self.rxStreamId)
                return;
            
            NSDictionary *header = @{
                                     @"rpt1Call" : [NSString stringWithCallsign:frame->header.rpt1Call],
                                     @"rpt2Call" : [NSString stringWithCallsign:frame->header.rpt2Call],
                                     @"myCall" : [NSString stringWithCallsign:frame->header.myCall],
                                     @"myCall2" : [NSString stringWithShortCallsign:frame->header.myCall2],
                                     @"urCall" : [NSString stringWithCallsign:frame->header.urCall],
                                     @"streamId" : [NSNumber numberWithUnsignedInteger:frame->id],
                                     @"time" : [NSDate date],
                                     @"message" : @""
                                     };
            
            NSLog(@"New stream %@", header);
            self.rxStreamId = frame->id;
            [self.delegate streamDidStart:header];
            self.qsoTimer = [[BTRNetworkTimer alloc] initWithTimeout:5.0 failureHandler: ^{
                [weakSelf terminateCurrentStream];
            }];
            break;
        }
        case 0x20:
            //  Ignore packets not in our current stream
            if(self.rxStreamId != frame->id)
                return;
            
            [self.qsoTimer ping];
            
            //  XXX This should be using a local variable set by the DataEngine.
            [self.delegate addData:frame->ambe.data streamId:self.rxStreamId];
            
            //  If the 0x40 bit of the sequence is set, this is the last packet of the stream.
            if(frame->sequence & 0x40) {
                [self terminateCurrentStream];
                frame->sequence &= ~0x40;
            }
            
            if(frame->sequence != self.rxSequence) {
                //  If the packet is more recent, reset the sequence, if not, wait for my next packet
                if(isSequenceAhead(frame->sequence, self.rxSequence, 21)) {
                    NSLog(@"Skipped packet: incoming %u, sequence = %u",frame->sequence, self.rxSequence);
                    self.rxSequence = frame->sequence;
                } else {
                    NSLog(@"Out of order packet: incoming = %u, sequence = %u\n", frame->sequence, self.rxSequence);
                    return;
                }
            }
            
            if(self.rxStreamId == 0)
                self.rxSequence = 0;
            else
                self.rxSequence = (self.rxSequence + 1) % 21;
            
            //  If streamId == 0, we are on the last packet of this stream.
            [self.vocoder decodeData:frame->ambe.voice lastPacket:(self.rxStreamId == 0)];
            break;
    }
}

-(void) sendAMBE:(void *)data lastPacket:(BOOL)last {
    if(self.linkState != LINKED)
        return;
    
    BTRLinkDriver __weak *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        //  If the sequence is 0, send a header packet.
        if(weakSelf.txSequence == 0) {
            NSLog(@"Sending header for stream %hu", weakSelf.txStreamId);
            struct dstar_frame header;
            memcpy(&header, &dstar_header_template, sizeof(struct dstar_frame));
            
            header.id = weakSelf.txStreamId;
            
            strncpy(header.header.myCall, weakSelf.myCall.paddedCall.UTF8String, sizeof(header.header.myCall));
            strncpy(header.header.myCall2, weakSelf.myCall2.paddedShortCall.UTF8String, sizeof(header.header.myCall2));
            strncpy(header.header.rpt1Call, weakSelf.myCall.paddedCall.UTF8String, sizeof(header.header.rpt1Call));
            strncpy(header.header.rpt2Call, weakSelf.linkTarget.paddedCall.UTF8String, sizeof(header.header.rpt2Call));
            
            header.header.sum = dstar_calc_sum(&header.header);
            
            [weakSelf sendFrame:&header];
            
            NSDictionary *streamInfo = @{
                                     @"rpt1Call" : weakSelf.myCall,
                                     @"rpt2Call" : weakSelf.linkTarget,
                                     @"myCall" : weakSelf.myCall,
                                     @"myCall2" : weakSelf.myCall2,
                                     @"urCall" : @"CQCQCQ",
                                     @"streamId" : [NSNumber numberWithUnsignedShort:weakSelf.txStreamId],
                                     @"time" : [NSDate date],
                                     @"direction" : @"TX",
                                     @"message" : @""
                                     };
            [weakSelf.delegate streamDidStart:streamInfo];

        }
        
        struct dstar_frame ambe;
        memcpy(&ambe, &dstar_ambe_template, sizeof(struct dstar_frame));
        ambe.sequence = weakSelf.txSequence;
        ambe.id = weakSelf.txStreamId;
        memcpy(&ambe.ambe.data, [self.delegate getDataForSequence:weakSelf.txSequence], sizeof(ambe.ambe.data));
        
        if(last) {
            [self.delegate streamDidEnd:[NSNumber numberWithUnsignedShort:weakSelf.txStreamId] atTime:[NSDate date]];
            weakSelf.txSequence = 0;
            weakSelf.txStreamId = (short) random();
            ambe.sequence |= 0x40;
        } else {
            memcpy(&ambe.ambe.voice, data, sizeof(ambe.ambe.voice));
            weakSelf.txSequence = (weakSelf.txSequence + 1) % 21;
        }
        
        [weakSelf sendFrame:&ambe];
    });
}


@end

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
#import "PortMapper.h"

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
    return [[[NSString alloc] initWithBytes:callsign length:8 encoding:NSASCIIStringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

+(NSString *)stringWithShortCallsign:(void *)callsign {
    return [[[NSString alloc] initWithBytes:callsign length:4 encoding:NSASCIIStringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

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
@property (nonatomic) int socket;
@property (nonatomic) dispatch_source_t dispatchSource;
@property (nonatomic) dispatch_source_t pollTimerSource;
@property (nonatomic, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, readwrite, copy) NSString * linkTarget;
@property (nonatomic) CFAbsoluteTime connectTime;
@property (nonatomic) PortMapper *portMapper;

@end

@implementation BTRLinkDriver

@synthesize vocoder = _vocoder;
@synthesize myCall = _myCall;
@synthesize myCall2 = _myCall2;
@synthesize delegate = _delegate;
@synthesize linkQueue = _linkQueue;

@dynamic rpt1Call;

-(id)init {
    self = [super init];
    if(self) {
        _linkTarget = @"";
        _linkState = UNLINKED;
        _rxStreamId = 0;
        _txStreamId = (short) random();
        _vocoder = nil;
        _rxSequence = 0;
        _txSequence = 0;
        
        dispatch_queue_attr_t dispatchQueueAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
        _writeQueue = dispatch_queue_create("net.nh6z.Buster.LinkWrite", dispatchQueueAttr);
        
        [[NSNotificationCenter defaultCenter] addObserverForName: PortMapperChangedNotification
                                                          object: nil
                                                           queue: [NSOperationQueue mainQueue]
                                                      usingBlock: ^(NSNotification *notification) {
                                                          PortMapper *mapper = (PortMapper *) notification.object;
                                                          if(mapper.error != noErr) {
                                                              NSLog(@"Error mapping port: %d", mapper.error);
                                                              return;
                                                          }
                                                          NSLog(@"Got the port mapping for %@:%d", mapper.publicAddress, mapper.publicPort);
                                                      }];
        
        [self open];
    }
    
    return self;
}

-(NSString *)rpt1Call {
    NSString *rpt1Call = self.myCall;
    NSString *module = [self.myCall.paddedCall substringWithRange:NSMakeRange(7, 1)];
    if([module isEqualToString:@" "])
        rpt1Call = [rpt1Call.paddedCall stringByReplacingCharactersInRange:NSMakeRange(7, 1) withString:@"D"];
    
    return rpt1Call;
}

+(NSSet *)keyPathsForValuesAffectingRpt1Call {
    return [NSSet setWithObjects:@"myCall", nil];
}

-(void)linkTo:(NSString *)linkTarget {
    // self.linkTarget = linkTarget;
    BTRLinkDriver __weak *weakSelf = self;
        
    dispatch_async(self.linkQueue, ^{
        [weakSelf.delegate destinationWillLink:linkTarget];
        
        NSString *reflectorAddress = [weakSelf getAddressForReflector:(NSString *)[[linkTarget substringWithRange:NSMakeRange(0, 7)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        if(!reflectorAddress) {
            //  XXX This really should never happen.
            NSError *error = [NSError errorWithDomain:@"BTRErrorDomain" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"Couldn't find reflector" }];
            [weakSelf.delegate destinationDidError:linkTarget error:error];
            
            NSLog(@"Couldn't find reflector %@", linkTarget);
            return;
        }
        
        struct sockaddr_in serverAddr = {
            .sin_len = sizeof(struct sockaddr_in),
            .sin_family = AF_INET,
            .sin_port = htons(weakSelf.serverPort),
            .sin_addr.s_addr = inet_addr([reflectorAddress cStringUsingEncoding:NSUTF8StringEncoding])
        };
        
        NSLog(@"Linking to %@ at %@", linkTarget, reflectorAddress);
        
        if(connect(weakSelf.socket, (const struct sockaddr *) &serverAddr, (socklen_t) sizeof(serverAddr))) {
            NSLog(@"Couldn't connect socket: %s\n", strerror(errno));
            return;
        }
        
        NSLog(@"Link Connection Complete");
        
        weakSelf.linkState = CONNECTED;
        
        dispatch_source_t retrySource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        dispatch_source_set_timer(retrySource, dispatch_time(DISPATCH_TIME_NOW, 0), 500ull * NSEC_PER_MSEC, 1ull * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(retrySource, ^{
            if(weakSelf.linkState != CONNECTED) {
                dispatch_source_cancel(retrySource);
            }
            
            if(CFAbsoluteTimeGetCurrent() > weakSelf.connectTime + 10.0) {
                NSError *error = [NSError errorWithDomain:@"BTRErrorDomain" code:4 userInfo:@{ NSLocalizedDescriptionKey: @"Timeout connecting to reflector" }];
                [weakSelf.delegate destinationDidError:linkTarget error:error];
                dispatch_source_cancel(retrySource);
                weakSelf.linkState = UNLINKED;
                weakSelf.linkTarget = @"";
            } else {
                [weakSelf sendLink];
            }
        });
        weakSelf.connectTime = CFAbsoluteTimeGetCurrent();
        dispatch_resume(retrySource);
        self.linkTarget = linkTarget;
    });
}

-(void)open {
    self.socket = socket(PF_INET, SOCK_DGRAM, 0);
    if(self.socket == -1) {
        NSLog(@"Error opening socket: %s\n", strerror(errno));
        return;
    }
    
    int one = 1;
    if(setsockopt(self.socket, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one))) {
        NSLog(@"Couldn't set socket to SO_REUSEADDR: %s\n", strerror(errno));
        return;
    }
    
    if(fcntl(self.socket, F_SETFL, O_NONBLOCK) == -1) {
        NSLog(@"Couldn't set socket to nonblocking: %s\n", strerror(errno));
        return;
    }

    struct sockaddr_in clientAddr = {
        .sin_len = sizeof(struct sockaddr_in),
        .sin_family = AF_INET,
        .sin_port = htons(self.clientPort),
        .sin_addr.s_addr = INADDR_ANY
    };
    
    if(bind(self.socket, (const struct sockaddr *) &clientAddr, (socklen_t) sizeof(clientAddr))) {
        NSLog(@"Couldn't bind gateway socket: %s\n", strerror(errno));
        return;
    }
    
    struct sockaddr_in boundAddress;
    socklen_t boundAddressLen;
    getsockname(self.socket, (struct sockaddr *) &boundAddress, &boundAddressLen);
    NSLog(@"Bound port %d for %@", ntohs(boundAddress.sin_port), NSStringFromClass([self class]));
    
    self.portMapper = [[PortMapper alloc] initWithPort:ntohs(boundAddress.sin_port)];
    self.portMapper.mapTCP = NO;
    self.portMapper.mapUDP = YES;
    self.portMapper.desiredPublicPort = self.clientPort;
    
    [self.portMapper open];
    
    self.dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) _socket, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    BTRLinkDriver __weak *weakSelf = self;
    dispatch_source_set_event_handler(_dispatchSource, ^{
        void *incomingPacket = malloc(weakSelf.packetSize);
        size_t bytesRead;
        
        do {
            bytesRead = recv(weakSelf.socket, incomingPacket, weakSelf.packetSize, 0);
            if(bytesRead == -1) {
                if(errno == EAGAIN)
                    break;
                NSLog(@"Couldn't read link packet: %s", strerror(errno));
                free(incomingPacket);
                return;
            }
            
            if(weakSelf.linkState == UNLINKED) {
                free(incomingPacket);
                return;
            }
            
            [weakSelf.linkTimer ping];
            
            [weakSelf processPacket:[NSData dataWithBytes:incomingPacket length:bytesRead]];
        } while(bytesRead > 0);
        free(incomingPacket);
    });
    
    dispatch_resume(self.dispatchSource);
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
    if(self.pollTimerSource)
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
-(BOOL)canHandleLinkTo:(NSString *)reflector {
    [self doesNotRecognizeSelector:_cmd];
}
-(NSArray<NSString *> *)destinations {
    [self doesNotRecognizeSelector:_cmd];
}
#pragma clang diagnostic pop

-(void)setLinkState:(enum linkState)linkState {
    if(_linkState == linkState)
        return;

    switch(linkState) {
        case UNLINKED: {
            [self.delegate destinationDidUnlink:self.linkTarget];
            [self stopPoll];
            self.linkTimer = nil;
            break;
        }
        case CONNECTED: {
            [self.delegate destinationDidConnect:self.linkTarget];
            break;
        }
        case LINKING: {
            [self startPoll];
            BTRLinkDriver __weak *weakSelf = self;
            self.linkTimer = [[BTRNetworkTimer alloc] initWithTimeout:30.0 failureHandler:^{
                [weakSelf unlink];
            }];
            break;
        }
        case LINKED: {
            [self.delegate destinationDidLink:self.linkTarget];
            if(_linkState == CONNECTED) {
                [self startPoll];
                BTRLinkDriver __weak *weakSelf = self;
                self.linkTimer = [[BTRNetworkTimer alloc] initWithTimeout:30.0 failureHandler:^{
                    [weakSelf unlink];
                }];
            }
        }
    }
               
    _linkState = linkState;
}

-(void) terminateCurrentStream {
    [self.delegate streamDidEnd:[NSNumber numberWithUnsignedInteger:self.rxStreamId] atTime:[NSDate date]];
    NSLog(@"Stream %d ends", self.rxStreamId);
    self.rxStreamId = 0;
    self.qsoTimer = nil;
}

-(void)unlink {
    BTRLinkDriver __weak *weakSelf = self;
    
    dispatch_async(self.linkQueue, ^{
        if(weakSelf.linkState == UNLINKED)
            return;
        
        int tries = 0;
        
        if(weakSelf.rxStreamId != 0)
            [weakSelf terminateCurrentStream];
        
        do {
            dispatch_sync(weakSelf.writeQueue, ^{
                [weakSelf sendUnlink];
            });
            usleep(USEC_PER_SEC / 10);  // XXX Don't like sleeping blindly here.
            if(tries++ > 10)
                break;
        } while(weakSelf.linkState != UNLINKED);
        
        weakSelf.linkTimer = nil;
        
        NSLog(@"Unlinked from %@", weakSelf.linkTarget);
        weakSelf.linkTarget = @"";
    });
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
            uint16 calculatedSum = dstar_calc_sum(&frame->header);
            if(self.hasReliableChecksum && frame->header.sum != 0xFFFF && frame->header.sum != calculatedSum) {
                NSLog(@"Header checksum mismatch: expected 0x%04hX calculated 0x%04hX", frame->header.sum, calculatedSum);
                return;
            }
            
            if(![self.linkTarget isEqualToString:[NSString stringWithCallsign:frame->header.rpt1Call]] &&
               ![self.linkTarget isEqualToString:[NSString stringWithCallsign:frame->header.rpt2Call]])
                return;
            
            if(self.rxStreamId) {
                if(self.rxStreamId == frame->id)
                    [self.qsoTimer ping];
                return;
            }
            
            //  XXX There can be null values here!
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
            strncpy(header.header.rpt1Call, weakSelf.rpt1Call.paddedCall.UTF8String, sizeof(header.header.rpt1Call));
            strncpy(header.header.rpt2Call, weakSelf.linkTarget.paddedCall.UTF8String, sizeof(header.header.rpt2Call));
            
            header.header.sum = dstar_calc_sum(&header.header);
            
            [weakSelf sendFrame:&header];
            
            NSDictionary *streamInfo = @{
                                     @"rpt1Call" : weakSelf.rpt1Call,
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
        
        [self.delegate getBytes:&ambe.ambe.data forSequence:weakSelf.txSequence];
        
        //memcpy(&ambe.ambe.data, [self.delegate getDataForSequence:weakSelf.txSequence], sizeof(ambe.ambe.data));
        
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

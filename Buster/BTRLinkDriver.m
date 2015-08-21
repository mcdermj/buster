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
#import "BTRGatewayHandler.h"
#import "BTRLinkDriverProtocol.h"
#import "BTRDataEngine.h"
#import "BTRSlowDataCoder.h"

#import <arpa/inet.h>
#import <sys/ioctl.h>

static const unsigned short ccittTab[] = {
    0x0000,0x1189,0x2312,0x329b,0x4624,0x57ad,0x6536,0x74bf,
    0x8c48,0x9dc1,0xaf5a,0xbed3,0xca6c,0xdbe5,0xe97e,0xf8f7,
    0x1081,0x0108,0x3393,0x221a,0x56a5,0x472c,0x75b7,0x643e,
    0x9cc9,0x8d40,0xbfdb,0xae52,0xdaed,0xcb64,0xf9ff,0xe876,
    0x2102,0x308b,0x0210,0x1399,0x6726,0x76af,0x4434,0x55bd,
    0xad4a,0xbcc3,0x8e58,0x9fd1,0xeb6e,0xfae7,0xc87c,0xd9f5,
    0x3183,0x200a,0x1291,0x0318,0x77a7,0x662e,0x54b5,0x453c,
    0xbdcb,0xac42,0x9ed9,0x8f50,0xfbef,0xea66,0xd8fd,0xc974,
    0x4204,0x538d,0x6116,0x709f,0x0420,0x15a9,0x2732,0x36bb,
    0xce4c,0xdfc5,0xed5e,0xfcd7,0x8868,0x99e1,0xab7a,0xbaf3,
    0x5285,0x430c,0x7197,0x601e,0x14a1,0x0528,0x37b3,0x263a,
    0xdecd,0xcf44,0xfddf,0xec56,0x98e9,0x8960,0xbbfb,0xaa72,
    0x6306,0x728f,0x4014,0x519d,0x2522,0x34ab,0x0630,0x17b9,
    0xef4e,0xfec7,0xcc5c,0xddd5,0xa96a,0xb8e3,0x8a78,0x9bf1,
    0x7387,0x620e,0x5095,0x411c,0x35a3,0x242a,0x16b1,0x0738,
    0xffcf,0xee46,0xdcdd,0xcd54,0xb9eb,0xa862,0x9af9,0x8b70,
    0x8408,0x9581,0xa71a,0xb693,0xc22c,0xd3a5,0xe13e,0xf0b7,
    0x0840,0x19c9,0x2b52,0x3adb,0x4e64,0x5fed,0x6d76,0x7cff,
    0x9489,0x8500,0xb79b,0xa612,0xd2ad,0xc324,0xf1bf,0xe036,
    0x18c1,0x0948,0x3bd3,0x2a5a,0x5ee5,0x4f6c,0x7df7,0x6c7e,
    0xa50a,0xb483,0x8618,0x9791,0xe32e,0xf2a7,0xc03c,0xd1b5,
    0x2942,0x38cb,0x0a50,0x1bd9,0x6f66,0x7eef,0x4c74,0x5dfd,
    0xb58b,0xa402,0x9699,0x8710,0xf3af,0xe226,0xd0bd,0xc134,
    0x39c3,0x284a,0x1ad1,0x0b58,0x7fe7,0x6e6e,0x5cf5,0x4d7c,
    0xc60c,0xd785,0xe51e,0xf497,0x8028,0x91a1,0xa33a,0xb2b3,
    0x4a44,0x5bcd,0x6956,0x78df,0x0c60,0x1de9,0x2f72,0x3efb,
    0xd68d,0xc704,0xf59f,0xe416,0x90a9,0x8120,0xb3bb,0xa232,
    0x5ac5,0x4b4c,0x79d7,0x685e,0x1ce1,0x0d68,0x3ff3,0x2e7a,
    0xe70e,0xf687,0xc41c,0xd595,0xa12a,0xb0a3,0x8238,0x93b1,
    0x6b46,0x7acf,0x4854,0x59dd,0x2d62,0x3ceb,0x0e70,0x1ff9,
    0xf78f,0xe606,0xd49d,0xc514,0xb1ab,0xa022,0x92b9,0x8330,
    0x7bc7,0x6a4e,0x58d5,0x495c,0x3de3,0x2c6a,0x1ef1,0x0f78
};

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
            NSLog(@"Timer firing");
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

-(void)terminateCurrentStream;
-(uint16)calculateChecksum:(struct dstar_header_data *)header;

@end

@implementation BTRLinkDriver

@synthesize vocoder = _vocoder;

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
        void *incomingPacket = malloc(self.packetSize);
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
    
    [self sendLink];

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
        case LINKING: {
            BTRLinkDriver __weak *weakSelf = self;
            NSDictionary *infoDict = @{ @"local": [NSString stringWithFormat:@"Connected to %@", self.linkTarget],
                                        @"reflector": self.linkTarget,
                                        @"status": @"" };
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:weakSelf userInfo:infoDict];
            });
            
            [self startPoll];
            
            self.linkTimer = [[BTRNetworkTimer alloc] initWithTimeout:30.0 failureHandler:^{
                [weakSelf unlink];
            }];
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
    BTRLinkDriver __weak *weakSelf = self;
    NSDictionary *streamData = @{
                                 @"streamId": [NSNumber numberWithUnsignedInteger:self.rxStreamId],
                                 @"time": [NSDate date]
                                 };
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName: BTRNetworkStreamEnd
                                                            object: weakSelf
                                                          userInfo: streamData
         ];
    });
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

- (uint16) calculateChecksum:(struct dstar_header_data *)header {
    unsigned short crc = 0xFFFF;
    
    for(char *packetPointer = (char *) header;
        packetPointer < (char *) &(header->sum);
        ++packetPointer) {
        crc = (crc >> 8) ^ ccittTab[(crc & 0x00FF) ^ *packetPointer];
    }
    
    crc = ~crc;
    
    return ((uint16) crc);
}

-(void)processFrame:(struct dstar_frame *)frame {
    BTRLinkDriver __weak *weakSelf = self;

    switch(frame->type) {
        case 0x10: {
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
            
            if(self.rxStreamId == 0) {
                NSLog(@"New stream %@", header);
                self.rxStreamId = frame->id;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName: BTRNetworkStreamStart
                                                                        object: weakSelf
                                                                      userInfo: header
                     ];
                });
                
                self.qsoTimer = [[BTRNetworkTimer alloc] initWithTimeout:5.0 failureHandler: ^{
                    [weakSelf terminateCurrentStream];
                }];
            }
            
            [self.qsoTimer ping];
            NSLog(@"Received header %@", header);
            break;
        }
        case 0x20:
            //  Ignore packets not in our current stream
            if(self.rxStreamId != frame->id)
                return;
            
            [self.qsoTimer ping];
            
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
            
            //  XXX These should be using a local variable set by the DataEngine.
            [[BTRDataEngine sharedInstance].slowData addData:frame->ambe.data streamId:self.rxStreamId];
            
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
            
            //  XXX This should get the global value
            strncpy(header.header.myCall, [[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"].paddedCall.UTF8String, sizeof(header.header.myCall));
            strncpy(header.header.myCall2, [[NSUserDefaults standardUserDefaults] stringForKey:@"myCall2"].paddedShortCall.UTF8String, sizeof(header.header.myCall2));
            strncpy(header.header.rpt1Call, [[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"].paddedCall.UTF8String, sizeof(header.header.rpt1Call));
            strncpy(header.header.rpt2Call, weakSelf.linkTarget.paddedCall.UTF8String, sizeof(header.header.rpt2Call));
            
            header.header.sum = [weakSelf calculateChecksum:&header.header];
            
            [weakSelf sendFrame:&header];
        }
        
        struct dstar_frame ambe;
        memcpy(&ambe, &dstar_ambe_template, sizeof(struct dstar_frame));
        ambe.sequence = weakSelf.txSequence;
        ambe.id = weakSelf.txStreamId;
        memcpy(&ambe.ambe.data, [[BTRDataEngine sharedInstance].slowData getDataForSequence:weakSelf.txSequence], sizeof(ambe.ambe.data));
        
        if(last) {
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

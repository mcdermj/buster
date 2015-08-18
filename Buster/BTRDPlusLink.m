//
//  BTRDPlusLink.m
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


#import "BTRDPlusLink.h"

#import <arpa/inet.h>
#import <sys/ioctl.h>

#import "BTRDPlusAuthenticator.h"
#import "BTRGatewayHandler.h"
#import "BTRDataEngine.h"
#import "BTRSlowDataCoder.h"

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

#pragma pack(push, 1)
struct dplus_packet {
    unsigned short length;
    union {
        struct {
            char type;
            char padding;
            union {
                char state;
                char ack[4];
                struct {
                    char repeater[16];
                    char magic[8];
                } module;
            };
        } link;
        struct {
            struct {
                char magic[4];
                char type;
                char unknown[4];
                char band[3];
                unsigned short id;
                char sequence;
            } header;
            union {
                struct {
                    char flags[3];
                    char rpt2Call[8];
                    char rpt1Call[8];
                    char urCall[8];
                    char myCall[8];
                    char myCall2[4];
                    unsigned short sum;
                } headerData;
                struct {
                    char voice[9];
                    char data[3];
                    char endPattern[6];
                } ambeData;
            };
        } data;
    };
};

#pragma pack(pop)

#define dplus_packet_size(a) ((a).length & 0x0FFF)
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

static const char DPLUS_TYPE_POLL = 0x00;
static const char DPLUS_TYPE_LINK = 0x18;
static const char DPLUS_TYPE_LINKMODULE = 0x04;

static const char DPLUS_END_PATTERN[] = { 0x55, 0x55, 0x55, 0x55, 0xC8, 0x7A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
static const char DPLUS_NULL_PATTERN[] = { 0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8 };

static const struct dplus_packet linkTemplate = {
    .length = 0x05,
    .link.type = DPLUS_TYPE_LINK,
    .link.padding = 0x00,
    .link.state = 0x01
};

static const struct dplus_packet unlinkTemplate = {
    .length = 0x05,
    .link.type = DPLUS_TYPE_LINK,
    .link.padding = 0x00,
    .link.state = 0x00
};

static const struct dplus_packet linkModuleTemplate = {
    .length = 0xC01C,
    .link.type = DPLUS_TYPE_LINKMODULE,
    .link.padding = 0x00,
    .link.module.repeater = "NH6Z",
    .link.module.magic = "DV019999"
};

static const struct dplus_packet pollPacket = {
    .length = 0x6003,
    .link.type = DPLUS_TYPE_POLL
};

static const struct dplus_packet headerTemplate = {
    .length = 0x803A,
    .data.header.magic = "DSVT",
    .data.header.type = 0x10,
    .data.header.unknown = { 0x00, 0x00, 0x00, 0x20 },
    .data.header.band = { 0x00, 0x00, 0x00 },
    .data.header.id = 0,
    .data.header.sequence = 0x80,
    .data.headerData.flags = { 0x00, 0x00, 0x00 },
    .data.headerData.myCall = "        ",
    .data.headerData.urCall = "CQCQCQ  ",
    .data.headerData.rpt1Call = "        ",
    .data.headerData.rpt2Call = "        ",
    .data.headerData.myCall2 = "    ",
    .data.headerData.sum = 0xFFFF
};

static const struct dplus_packet ambeTemplate = {
    .length = 0x801D,
    .data.header.magic = "DSVT",
    .data.header.type = 0x20,
    .data.header.unknown = { 0x00, 0x00, 0x00, 0x20 },
    .data.header.band = { 0x00, 0x00, 0x00 },
    .data.header.id = 0,
    .data.header.sequence = 0,
    .data.ambeData.voice = { 0 },
    .data.ambeData.data = { 0 },
    .data.ambeData.endPattern = { 0 }
};


@interface BTRDPlusLink ()

@property (nonatomic, readwrite, getter=isLinked) BOOL linked;
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

@implementation BTRDPlusLink

@synthesize vocoder = _vocoder;

- (id) init {
    self = [super init];
    if(self) {
        _linkTarget = @"";
        _linked = NO;
        _rxStreamId = 0;
        _txStreamId = (short) random();
        _lastPacketTime = CFAbsoluteTimeGetCurrent() + (3600.0 * 24.0 * 365.0);
        _lastLinkPacketTime = CFAbsoluteTimeGetCurrent() + (3600.0 * 24.0 * 365.0);
        _vocoder = nil;
        _rxSequence = 0;
        _txSequence = 0;
        
        dispatch_queue_attr_t dispatchQueueAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
        _writeQueue = dispatch_queue_create("net.nh6z.Dummy.DPlusWrite", dispatchQueueAttr);
        
        _socket = socket(PF_INET, SOCK_DGRAM, 0);
        if(_socket == -1) {
            NSLog(@"Error opening socket: %s\n", strerror(errno));
            return nil;
        }
        
        int one = 1;
        if(setsockopt(_socket, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one))) {
            NSLog(@"Couldn't set socket to SO_REUSEADDR: %s\n", strerror(errno));
            return nil;
        }
        
        if(fcntl(_socket, F_SETFL, O_NONBLOCK) == -1) {
            NSLog(@"Couldn't set socket to nonblocking: %s\n", strerror(errno));
            return nil;
        }
        
        struct sockaddr_in addr = {
            .sin_len = sizeof(struct sockaddr_in),
            .sin_family = AF_INET,
            .sin_port = htons(20001),
            .sin_addr.s_addr = INADDR_ANY
        };
        
        if(bind(_socket, (const struct sockaddr *) &addr, (socklen_t) sizeof(addr))) {
            NSLog(@"Couldn't bind gateway socket: %s\n", strerror(errno));
            return nil;
        }
        
        dispatch_queue_t mainQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        _dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) _socket, 0, mainQueue);
        BTRDPlusLink __weak *weakSelf = self;
        dispatch_source_set_event_handler(_dispatchSource, ^{
            struct dplus_packet incomingPacket = { 0 };
            size_t packetSize;
            
            do {
                packetSize = recv(weakSelf.socket, &incomingPacket, sizeof(struct dplus_packet), 0);
                if(packetSize == -1) {
                    if(errno == EAGAIN)
                        break;
                    NSLog(@"Couldn't read DPlus packet: %s", strerror(errno));
                    return;
                }
                
                weakSelf.lastLinkPacketTime = CFAbsoluteTimeGetCurrent();
                
                switch(incomingPacket.length & 0xF000) {
                    case 0x8000:
                        if(strncmp(incomingPacket.data.header.magic, "DSVT", 4)) {
                            NSLog(@"Invalid magic on a DPlus data packet: %s", incomingPacket.data.header.magic);
                            return;
                        }
                        [weakSelf processDataPacket:&incomingPacket];
                        break;
                    case 0x6000:
                        [weakSelf processPollPacket:&incomingPacket];
                        break;
                    case 0xC000:
                    case 0x0000:
                        [weakSelf processLinkPacket:&incomingPacket];
                        break;
                    default:
                        NSLog(@"Invalid flag byte 0x%02X", incomingPacket.length & 0xF000);
                        break;
                }
            } while(packetSize > 0);
        });
        
        //  Set a watchdog timer for incoming transmissions.  If we don't receive a packet within 5s, terminate the stream.
        _watchdogTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, mainQueue);
        dispatch_source_set_timer(_watchdogTimerSource, dispatch_time(DISPATCH_TIME_NOW, 0), 500ull * NSEC_PER_MSEC, 100ull * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(_watchdogTimerSource, ^{
            if(CFAbsoluteTimeGetCurrent() > weakSelf.lastPacketTime + 5.0) {
                NSLog(@"Watchdog terminating stream %d due to inactivity for %f sec.", weakSelf.rxStreamId, CFAbsoluteTimeGetCurrent() - weakSelf.lastPacketTime);
                [weakSelf terminateCurrentStream];
            }
        });
        
        //  Set a watchdog timer for the link itself.  If we don't hear a packet from the link target in 30 seconds, terminate the link.
        _linkWatchdogTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, mainQueue);
        dispatch_source_set_timer(_linkWatchdogTimerSource, dispatch_time(DISPATCH_TIME_NOW, 0), 3ull * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);
        dispatch_source_set_event_handler(_linkWatchdogTimerSource, ^{
            if(CFAbsoluteTimeGetCurrent() > weakSelf.lastLinkPacketTime + 30.0) {
                NSLog(@"Watchdog terminating link due to inactivity for %f sec.", CFAbsoluteTimeGetCurrent() - weakSelf.lastLinkPacketTime);
                [weakSelf unlink];
            }
        });
        
        //  Poll the link target every second.
        _pollTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, mainQueue);
        dispatch_source_set_timer(_pollTimerSource, dispatch_time(DISPATCH_TIME_NOW, 0), 1ull * NSEC_PER_SEC, 100ull * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(_pollTimerSource, ^{
            [weakSelf sendPacket:pollPacket];
        });
    }
    
    return self;
}

- (void) sendPacket:(const struct dplus_packet)packet {
    dispatch_async(self.writeQueue, ^{
        size_t bytesSent = send(self.socket, &packet, dplus_packet_size(packet), 0);
        if(bytesSent == -1) {
            NSLog(@"Couldn't write link request: %s", strerror(errno));
            return;
        }
        if(bytesSent != dplus_packet_size(packet)) {
            NSLog(@"Short write on link");
            return;
        }
    });
}

- (void)processLinkPacket:(struct dplus_packet *)packet {
    switch(packet->link.type) {
        case DPLUS_TYPE_LINK:
            switch(packet->link.state) {
                case 0x00: {
                    NSLog(@"DPlus reports unlinked");
                    NSDictionary *infoDict = @{ @"local": @"Unlinked",
                                                @"reflector": self.linkTarget,
                                                @"status": @"" };
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:self userInfo:infoDict];
                    });

                    dispatch_suspend(self.dispatchSource);
                    dispatch_suspend(self.pollTimerSource);
                    dispatch_suspend(self.linkWatchdogTimerSource);
                    self.linked = NO;
                    break;
                }
                case 0x01: {
                    NSLog(@"DPlus reports linked");
                    NSDictionary *infoDict = @{ @"local": [NSString stringWithFormat:@"Connected to %@", self.linkTarget],
                                                @"reflector": self.linkTarget,
                                                @"status": @"" };
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:self userInfo:infoDict];
                    });
                    
                    dispatch_resume(self.pollTimerSource);
                    dispatch_resume(self.linkWatchdogTimerSource);

                    struct dplus_packet linkPacket = { 0 };
                    memcpy(&linkPacket, &linkModuleTemplate, sizeof(linkPacket));
                
                    memcpy(linkPacket.link.module.repeater, [[BTRDPlusAuthenticator sharedInstance].authCall cStringUsingEncoding:NSUTF8StringEncoding], [BTRDPlusAuthenticator sharedInstance].authCall.length);
                    [self sendPacket:linkPacket];
                    break;
                }
                default:
                    NSLog(@"Received unknown value for link packet: 0x%02X", packet->link.state);
                    break;
            }
            break;
        case DPLUS_TYPE_LINKMODULE:
            if(!strncmp(packet->link.module.repeater, "OKRW", 4)) {
                NSDictionary *infoDict = @{ @"local": [NSString stringWithFormat:@"Linked to %@", self.linkTarget],
                                            @"reflector": self.linkTarget,
                                            @"status": @"" };
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:self userInfo:infoDict];
                });

                NSLog(@"Received ACK from repeater, we are now linked");
                self.linked = YES;
            } else if(!strncmp(packet->link.module.repeater, "BUSY", 4)) {
                NSLog(@"Received NACK from repeater, link failed");
                [self unlink];
            } else {
                NSLog(@"Unknown link packet received");
            }
            break;
        case 0x0B:
            //  This is some sort of ending packet for a transmission.  Need to investigate further.
            break;
        default:
            NSLog(@"Received unknown packet type 0x%02X", packet->link.type);
            NSLog(@"Dump: %@", [NSData dataWithBytes:packet length:sizeof(struct dplus_packet)]);
            break;
    }
}

- (void)processPollPacket:(struct dplus_packet *)packet {
    if(packet->link.type != DPLUS_TYPE_POLL) {
        NSLog(@"Received invalid poll packet");
        return;
    }
}

- (void)processDataPacket:(struct dplus_packet *)packet {
    switch(packet->data.header.type) {
        case 0x10: {
            NSDictionary *header = @{
                                     @"rpt1Call" : call_to_nsstring(packet->data.headerData.rpt1Call),
                                     @"rpt2Call" : call_to_nsstring(packet->data.headerData.rpt2Call),
                                     @"myCall" : call_to_nsstring(packet->data.headerData.myCall),
                                     @"myCall2" : call_to_nsstring(packet->data.headerData.myCall2),
                                     @"urCall" : call_to_nsstring(packet->data.headerData.urCall),
                                     @"streamId" : [NSNumber numberWithUnsignedInteger:packet->data.header.id],
                                     @"time" : [NSDate date],
                                     @"message" : @""
            };
            
            if(![header[@"rpt1Call"] isEqualToString:self.linkTarget] && ![header[@"rpt2Call"] isEqualToString:self.linkTarget]) {
                // NSLog(@"Received header for uninterested module");
                return;
            }
            
            if(self.rxStreamId == 0) {
                NSLog(@"New stream %@", header);
                self.rxStreamId = packet->data.header.id;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName: BTRNetworkStreamStart
                                                                        object: self
                                                                      userInfo: header
                     ];
                });
                dispatch_resume(self.watchdogTimerSource);
            }
            
            self.lastPacketTime = CFAbsoluteTimeGetCurrent();
            // NSLog(@"Received header %@", header);
            break;
        }
        case 0x20:
            //  Ignore packets not in our current stream
            if(self.rxStreamId != packet->data.header.id)
                return;
            
            self.lastPacketTime = CFAbsoluteTimeGetCurrent();
            
            //  If the 0x40 bit of the sequence is set, this is the last packet of the stream.
            if(packet->data.header.sequence & 0x40) {
                [self terminateCurrentStream];
                packet->data.header.sequence &= ~0x40;
            }
            
            if(packet->data.header.sequence != self.rxSequence) {
                //  If the packet is more recent, reset the sequence, if not, wait for my next packet
                if(isSequenceAhead(packet->data.header.sequence, self.rxSequence, 21)) {
                    NSLog(@"Skipped packet: incoming %u, sequence = %u",packet->data.header.sequence, self.rxSequence);
                    self.rxSequence = packet->data.header.sequence;
                } else {
                    NSLog(@"Out of order packet: incoming = %u, sequence = %u\n", packet->data.header.sequence, self.rxSequence);
                    return;
                }
            }
            
             //  XXX These should be using a local variable set by the DataEngine.
            [[BTRDataEngine sharedInstance].slowData addData:packet->data.ambeData.data streamId:self.rxStreamId];
            
            if(self.rxStreamId == 0)
                self.rxSequence = 0;
            else
                self.rxSequence = (self.rxSequence + 1) % 21;
            
            //  If streamId == 0, we are on the last packet of this stream.
            [self.vocoder decodeData: packet->data.ambeData.voice lastPacket:(self.rxStreamId == 0)];

            
            // NSLog(@"AMBE packet received for stream %d", packet->data.header.id);
            break;
    }
}

-(void) terminateCurrentStream {
    NSDictionary *streamData = @{
                                 @"streamId": [NSNumber numberWithUnsignedInteger:self.rxStreamId],
                                 @"time": [NSDate date]
                                 };
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName: BTRNetworkStreamEnd
                                                            object: self
                                                          userInfo: streamData
         ];
    });
    NSLog(@"Stream %d ends", self.rxStreamId);
    self.rxStreamId = 0;
    self.lastPacketTime = CFAbsoluteTimeGetCurrent() + (3600.0 * 24.0 * 365.0);
    dispatch_suspend(self.watchdogTimerSource);
}


- (void) linkTo:(NSString *)linkTarget {
    
    if(self.isLinked)
        [self unlink];
    
    NSDictionary *infoDict = @{ @"local": [NSString stringWithFormat:@"Linking to %@", linkTarget],
                                @"reflector": linkTarget,
                                @"status": @"" };
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:self userInfo:infoDict];
    });

    
    NSString *targetReflector = [[linkTarget substringWithRange:NSMakeRange(0, 7)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSUInteger reflectorIndex = [[BTRDPlusAuthenticator sharedInstance].reflectorList indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [obj[@"name"] isEqualToString:targetReflector];
    }];
    if(reflectorIndex == NSNotFound) {
       infoDict = @{ @"local": [NSString stringWithFormat:@"Couldn't find %@", linkTarget],
                                    @"reflector": linkTarget,
                                    @"status": @"" };
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:self userInfo:infoDict];
        });

        NSLog(@"Couldn't find reflector %@", linkTarget);
        return;
    }
    
    struct sockaddr_in addr = {
        .sin_len = sizeof(struct sockaddr_in),
        .sin_family = AF_INET,
        .sin_port = htons(20001),
        .sin_addr.s_addr = inet_addr([[BTRDPlusAuthenticator sharedInstance].reflectorList[reflectorIndex][@"address"] cStringUsingEncoding:NSUTF8StringEncoding])
    };

    NSLog(@"Linking to %@ at %@", linkTarget, [BTRDPlusAuthenticator sharedInstance].reflectorList[reflectorIndex][@"address"]);
    
    if(connect(self.socket, (const struct sockaddr *) &addr, (socklen_t) sizeof(addr))) {
        NSLog(@"Couldn't connect socket: %s\n", strerror(errno));
        return;
    }
    
    NSLog(@"Link Connection Complete");
    
    dispatch_resume(self.dispatchSource);
    
    [self sendPacket:linkTemplate];
    
    self.linkTarget = [linkTarget copy];
}

-(void)unlink {
    if(!self.isLinked)
        return;
    
    BTRDPlusLink __weak *weakSelf = self;
    int tries = 0;
    
    if(self.rxStreamId != 0)
        [self terminateCurrentStream];

    do {
        dispatch_sync(self.writeQueue, ^{
            [weakSelf sendPacket:unlinkTemplate];
        });
        usleep(USEC_PER_SEC / 10);  // XXX Don't like sleeping blindly here.
        if(tries++ > 10)
            break;
    } while(self.isLinked);
    
    self.lastLinkPacketTime = CFAbsoluteTimeGetCurrent() + (3600.0 * 24.0 * 365.0);
    
    NSLog(@"Unlinked from %@", self.linkTarget);
    self.linkTarget = @"";
}

- (void) dealloc  {
    dispatch_cancel(self.dispatchSource);
    dispatch_cancel(self.watchdogTimerSource);
    dispatch_cancel(self.linkWatchdogTimerSource);
    dispatch_cancel(self.pollTimerSource);
    close(self.socket);
}

-(void) sendAMBE:(void *)data lastPacket:(BOOL)last {
    if(!self.isLinked)
        return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        struct dplus_packet packet = {};
        
        //  If the sequence is 0, send a header packet.
        if(self.txSequence == 0) {
            NSLog(@"Sending header");
            memcpy(&packet, &headerTemplate, sizeof(struct dplus_packet));
            
            packet.data.header.id = self.txStreamId;
            
            //  XXX This should get the global value
            strncpy(packet.data.headerData.myCall, [[[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"] stringByPaddingToLength:8 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.headerData.myCall));
            strncpy(packet.data.headerData.myCall2, [[[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall2"] stringByPaddingToLength:4 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.headerData.myCall2));
            
            NSString *rpt1Call = [NSString stringWithFormat:@"%@ D", [[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"] stringByPaddingToLength:6 withString:@" " startingAtIndex:0]];
            strncpy(packet.data.headerData.rpt1Call, [[rpt1Call stringByPaddingToLength:8 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.headerData.rpt1Call));
            
            strncpy(packet.data.headerData.rpt2Call, [[self.linkTarget stringByPaddingToLength:8 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.headerData.rpt2Call));

            packet.data.headerData.sum = [self calculateChecksum:packet];
            
            [self sendPacket:packet];
        }
        
        memcpy(&packet, &ambeTemplate, sizeof(struct dplus_packet));
        packet.data.header.sequence = self.txSequence;
        packet.data.header.id = self.txStreamId;
        memcpy(&packet.data.ambeData.voice, data, sizeof(packet.data.ambeData.voice));
        memcpy(&packet.data.ambeData.data, [[BTRDataEngine sharedInstance].slowData getDataForSequence:self.txSequence], sizeof(packet.data.ambeData.data));
        
        if(last) {
            self.txSequence = 0;
            self.txStreamId = (short) random();
            packet.data.header.sequence &= 0x40;
            packet.length = 0x8020;
            memcpy(&packet.data.ambeData.endPattern, DPLUS_END_PATTERN, sizeof(packet.data.ambeData.endPattern));
            memcpy(&packet.data.ambeData.voice, DPLUS_NULL_PATTERN, sizeof(packet.data.ambeData.voice));
        } else {
            self.txSequence = (self.txSequence + 1) % 21;
        }
        
        [self sendPacket:packet];
    });
}

- (uint16) calculateChecksum:(struct dplus_packet)packet {
    unsigned short crc = 0xFFFF;
    
    int length = (sizeof(packet.data.headerData.myCall) * 4) +
        sizeof(packet.data.headerData.myCall2) +
        sizeof(packet.data.headerData.flags);
    
    for(char *packetPointer = (char *) &packet.data.headerData;
        packetPointer < ((char *) &packet.data.headerData) + length;  // XXX Can this be &packet.data.headerData.sum?
        ++packetPointer) {
        crc = (crc >> 8) ^ ccittTab[(crc & 0x00FF) ^ *packetPointer];
    }
    
    crc = ~crc;
    
    return ((uint16) crc);
}

@end

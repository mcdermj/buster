//
//  BTRGatewayHandler.m
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

#import "BTRGatewayHandler.h"

#import <arpa/inet.h>
#import <sys/ioctl.h>

NSString * const BTRNetworkHeaderReceived = @"BTRNetworkHeaderReceived";
NSString * const BTRNetworkStreamEnd = @"BTRNetworkStreamEnd";
NSString * const BTRNetworkStreamStart = @"BTRNetworkStreamStart";
NSString * const BTRRepeaterInfoReceived = @"BTRRepeaterInfoReceived";

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

struct gatewayPacket {
    char magic[4];
    unsigned char packetType;
    union {
        struct {
            uint16 streamId;
            uint8 lastPacket;
            uint8 flags[3];
            uint8 rpt1Call[8];
            uint8 rpt2Call[8];
            uint8 urCall[8];
            uint8 myCall[8];
            uint8 myCall2[4];
            uint16 checksum;
        } dstarHeader;
        struct {
            uint16 streamId;
            uint8 sequence;
            uint8 errors;
            uint8 ambeData[9];
            uint8 slowData[3];
        } dstarData;
        struct {
            char local[20];
            char status;
            char reflector[8];
        } networkText;
        char pollText[250];
    } payload;
} __attribute__((packed));


static const char GW_PACKET_TYPE_HEADER = 0x20;
static const char GW_PACKET_TYPE_DATA = 0x21;
static const char GW_PACKET_TYPE_POLL = 0x0A;

static const struct gatewayPacket pollPacket = {
    .magic = "DSRP",
    .packetType = GW_PACKET_TYPE_POLL,
    .payload.pollText = "Dummy v1.0 (Mac)"
};


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

@interface BTRGatewayHandler () {
    int gatewaySocket;
    dispatch_source_t dispatchSource;
    dispatch_source_t pollTimerSource;
    dispatch_source_t watchdogTimerSource;
    dispatch_queue_t dispatchQueue;
    uint16 txStreamId;
    uint8 txSequence;
    uint8 rxSequence;
    BOOL running;
    NSThread *readThread;
    
    enum {
        GWY_STOPPED,
        GWY_STARTED
    } status;
}

@property (nonatomic, readwrite) BTRSlowDataHandler *slowData;
@property (nonatomic, assign) uint16 rxStreamId;
@property (nonatomic, assign) CFAbsoluteTime lastPacketTime;

- (NSData *) constructRemoteAddrStruct;
- (NSData *) constructLocalAddrStruct;
- (void) processPacket:(struct gatewayPacket *)packet;
- (uint16) calculateChecksum:(struct gatewayPacket)packet;
- (void) sendBlankTransmissionWithUr:(NSString *)urCall;
- (BOOL)sendPacket:(const struct gatewayPacket *)packet;
- (void) fillHeader:(struct gatewayPacket *)packet;

@end

@implementation BTRGatewayHandler

#pragma mark - Initializers

- (id) init {
    self = [super init];
    if(self) {
        gatewaySocket = 0;
        _rxStreamId = 0;
        txStreamId = htons((short) random());
        
        _gatewayPort = 0;
        _repeaterPort = 0;
        _gatewayAddr = @"";
        
        _vocoder = nil;
        
        self.xmitMyCall = @"";
        self.xmitMyCall2 = @"";
        self.xmitUrCall = @"";
        self.xmitRpt1Call = @"";
        self.xmitRpt2Call = @"";
        
        status = GWY_STOPPED;
        
        _lastPacketTime = CFAbsoluteTimeGetCurrent() + (3600.0 * 24.0 * 365.0);
        
        txSequence = 0;
        
        _slowData = [[BTRSlowDataHandler alloc] init];
        self.slowData.message = @"";
        
        dispatch_queue_attr_t dispatchQueueAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
        dispatchQueue = dispatch_queue_create("net.nh6z.Dummy.NetworkIO", dispatchQueueAttr);
    }
    return self;
}

#pragma mark - Accessors

- (void) setGatewayAddr:(NSString *)gatewayAddr {
    _gatewayAddr = gatewayAddr;
    
    if(status == GWY_STARTED) {
        [self stop];
        [self start];
    }
}

- (void) setGatewayPort:(NSUInteger)gatewayPort {
    _gatewayPort = gatewayPort;
    
    if(status == GWY_STARTED) {
        [self stop];
        [self start];
    }
}

- (void) setRepeaterPort:(NSUInteger)repeaterPort {
    _repeaterPort = repeaterPort;
    
    if(status == GWY_STARTED) {
        [self stop];
        [self start];
    }
}

- (void) setXmitMyCall2:(NSString *)xmitMyCall2 {
    _xmitMyCall2 = [xmitMyCall2 stringByPaddingToLength:4 withString:@" " startingAtIndex:0];
}

- (void) setXmitMyCall:(NSString *)xmitMyCall {
    _xmitMyCall = [xmitMyCall stringByPaddingToLength:8 withString:@" " startingAtIndex:0];
}

- (void) setXmitUrCall:(NSString *)xmitUrCall {
    _xmitUrCall = [xmitUrCall stringByPaddingToLength:8 withString:@" " startingAtIndex:0];
}

- (void) setXmitRpt1Call:(NSString *)xmitRpt1Call {
    _xmitRpt1Call = [xmitRpt1Call stringByPaddingToLength:8 withString:@" " startingAtIndex:0];
}

- (void) setXmitRpt2Call:(NSString *)xmitRpt2Call {
    _xmitRpt2Call = [xmitRpt2Call stringByPaddingToLength:8 withString:@" " startingAtIndex:0];
}

- (void) terminateIncomingStream {
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
    
    dispatch_suspend(watchdogTimerSource);
    
    self.rxStreamId = 0;
    self.lastPacketTime = CFAbsoluteTimeGetCurrent() + (3600.0 * 24.0 * 365.0);
}


#pragma mark - Flow Control

- (BOOL) start {
    gatewaySocket = socket(PF_INET, SOCK_DGRAM, 0);
    if(gatewaySocket == -1) {
        NSLog(@"Error opening socket: %s\n", strerror(errno));
        return NO;
    }
    
    int one = 1;
    if(setsockopt(gatewaySocket, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one))) {
        NSLog(@"Couldn't set socket to SO_REUSEADDR: %s\n", strerror(errno));
        return NO;
    }
    
    if(fcntl(gatewaySocket, F_SETFL, O_NONBLOCK) == -1) {
        NSLog(@"Couldn't set socket to nonblocking: %s\n", strerror(errno));
        return NO;
    }
    
    NSData *addr = [self constructLocalAddrStruct];
    if(bind(gatewaySocket, (const struct sockaddr *) [addr bytes], (socklen_t) [addr length])) {
        NSLog(@"Couldn't bind gateway socket: %s\n", strerror(errno));
        return NO;
    }
    
    addr = [self constructRemoteAddrStruct];
    if(connect(gatewaySocket, (const struct sockaddr *) [addr bytes], (socklen_t) [addr length])) {
        NSLog(@"Couldn't connect socket: %s\n", strerror(errno));
        return NO;
    }
    
    dispatch_queue_t mainQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) gatewaySocket, 0, mainQueue);
    BTRGatewayHandler __weak *weakSelf = self;
    dispatch_source_set_event_handler(dispatchSource, ^{
        size_t packetSize;
        struct gatewayPacket incomingPacket;
        
        do {
            packetSize = recv(gatewaySocket, &incomingPacket, sizeof(struct gatewayPacket), 0);
            if(packetSize == -1) {
                if(errno == EAGAIN) break;
                NSLog(@"Couldn't read packet: %s\n", strerror(errno));
                return;
            }
            
            [weakSelf processPacket:&incomingPacket];
        } while(packetSize > 0);
    });
    
    dispatch_resume(dispatchSource);
    
    //  XXX Should set up a timer here for the poll interval.
    //  XXX This should eventually be put on the read serial queue.
    pollTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_timer(pollTimerSource, dispatch_walltime(NULL, 0), 60ull * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);
    dispatch_source_set_event_handler(pollTimerSource, ^{
        NSLog(@"Sending Poll\n");
        if(![self sendPacket:&pollPacket])
            return;
    });
    dispatch_resume(pollTimerSource);
    
    watchdogTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, mainQueue);
    dispatch_source_set_timer(watchdogTimerSource, dispatch_time(DISPATCH_TIME_NOW, 0), 500ull * NSEC_PER_MSEC, 100ull * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(watchdogTimerSource, ^{
        if(CFAbsoluteTimeGetCurrent() > weakSelf.lastPacketTime + 5.0) {
            NSLog(@"Watchdog terminating stream %d due to inactivity for %f sec.", weakSelf.rxStreamId, CFAbsoluteTimeGetCurrent() - weakSelf.lastPacketTime);
            [weakSelf terminateIncomingStream];
        }
    });
    
    NSLog(@"Completed socket setup\n");
    
    status = GWY_STARTED;
    
    return YES;
}

- (void) stop {
    if(status == GWY_STARTED) {
        dispatch_source_cancel(dispatchSource);
        dispatch_source_cancel(pollTimerSource);
    }
    
    close(gatewaySocket);
}

#pragma mark - Linking

- (void) linkTo:(NSString *)reflector {
    dispatch_async(dispatchQueue, ^{
        NSMutableString *linkCmd = [NSMutableString stringWithString:reflector];
        [linkCmd deleteCharactersInRange:NSMakeRange(6, 1)];
        [linkCmd appendString:@"L"];

        [self sendBlankTransmissionWithUr:linkCmd];
    });
}

- (void) unlink {
    [self sendBlankTransmissionWithUr:@"       U"];
}

#pragma mark - Sending to gateway

- (void) sendBlankTransmissionWithUr:(NSString *)urCall {
    dispatch_async(dispatchQueue, ^{
        struct gatewayPacket packet = {};
        short linkStreamId;
        
        memcpy(&packet.magic, "DSRP", sizeof(packet.magic));
        packet.packetType = GW_PACKET_TYPE_HEADER;
        
        strncpy((char *) packet.payload.dstarHeader.urCall, [urCall cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.payload.dstarHeader.urCall));
        
        [self fillHeader:&packet];
        
        linkStreamId = htons((short) random());
        packet.payload.dstarHeader.streamId = linkStreamId;
        
        packet.payload.dstarHeader.checksum = [self calculateChecksum:packet];
        
        if(![self sendPacket:&packet])
            return;
        
        //  Send the end stream packet
        packet.packetType = GW_PACKET_TYPE_DATA;
        memset(&packet.payload, 0, sizeof(packet.payload));
        packet.payload.dstarData.streamId = linkStreamId;
        packet.payload.dstarData.sequence = 0x40;
        
        if(![self sendPacket:&packet])
            return;
        
    });
}


- (void) sendAMBE:(void *)data lastPacket:(BOOL)last {
    char *ambeData = malloc(sizeof(((struct gatewayPacket *)0)->payload.dstarData.ambeData));
    memcpy(ambeData, data, sizeof(((struct gatewayPacket *)0)->payload.dstarData.ambeData));

    dispatch_async(dispatchQueue, ^{
        struct gatewayPacket packet = {};
        
        memcpy(&packet.magic, "DSRP", sizeof(packet.magic));
        packet.payload.dstarHeader.streamId = txStreamId;
        
        if(txSequence == 0) {
            packet.packetType = GW_PACKET_TYPE_HEADER;
            strncpy((char *) packet.payload.dstarHeader.urCall, [self.xmitUrCall cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.payload.dstarHeader.urCall));
            
            [self fillHeader:&packet];
            
            packet.payload.dstarHeader.checksum = [self calculateChecksum:packet];
            
            if(![self sendPacket:&packet])
                return;
        }
        
        packet.packetType = GW_PACKET_TYPE_DATA;
        memcpy(&packet.payload.dstarData.ambeData, ambeData, sizeof(packet.payload.dstarData.ambeData));
        packet.payload.dstarData.sequence = txSequence;
        
        memcpy(&packet.payload.dstarData.slowData, [self.slowData getDataForSequence:txSequence], sizeof(packet.payload.dstarData.slowData));
        
        packet.payload.dstarData.errors = 0;
        
        if(last) {
            txSequence = 0;
            txStreamId = htons((short) random());
            packet.payload.dstarData.sequence &= 0x40;
        } else {
            txSequence = (txSequence + 1) % 21;
        }
        
        [self sendPacket:&packet];
        
        free(ambeData);
    });
}

- (BOOL)sendPacket:(const struct gatewayPacket *)packet {
    size_t packetLen = sizeof(packet->magic) + sizeof(packet->packetType);
    
    switch(packet->packetType) {
        case GW_PACKET_TYPE_DATA:
            packetLen += sizeof(packet->payload.dstarData);
            break;
        case GW_PACKET_TYPE_HEADER:
            packetLen += sizeof(packet->payload.dstarHeader);
            break;
        case GW_PACKET_TYPE_POLL:
            packetLen += strlen(packet->payload.pollText) + 1;
            break;
        default:
            NSLog(@"Unknown packet type for transmission: 0x%02x", packet->packetType);
            return NO;
            break;
    }
    if(send(gatewaySocket, packet, packetLen, 0) == -1) {
        NSLog(@"Couldn't send packet: %s\n", strerror(errno));
        return NO;
    }
    return YES;
}

#pragma mark - Internal Methods

- (void) fillHeader:(struct gatewayPacket *)packet {
    strncpy((char *) packet->payload.dstarHeader.myCall, [self.xmitMyCall cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet->payload.dstarHeader.myCall));
    strncpy((char *) packet->payload.dstarHeader.rpt2Call, [self.xmitRpt2Call cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet->payload.dstarHeader.rpt1Call));
    strncpy((char *) packet->payload.dstarHeader.rpt1Call, [self.xmitRpt1Call cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet->payload.dstarHeader.rpt2Call));
    strncpy((char *) packet->payload.dstarHeader.myCall2, [self.xmitMyCall2 cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet->payload.dstarHeader.myCall2));
}

- (uint16) calculateChecksum:(struct gatewayPacket)packet {
    unsigned short crc = 0xFFFF;
    
    int length = (sizeof(packet.payload.dstarHeader.myCall) * 4) +
    sizeof(packet.payload.dstarHeader.myCall2) +
    sizeof(packet.payload.dstarHeader.flags);
    
    for(char *packetPointer = (char *) &packet.payload.dstarHeader.flags;
        packetPointer < ((char *) &packet.payload.dstarHeader.flags) + length;
        ++packetPointer) {
        crc = (crc >> 8) ^ ccittTab[(crc & 0x00FF) ^ *packetPointer];
    }
    
    crc = ~crc;
    
    return ((uint16) crc);
}

- (NSData *) constructRemoteAddrStruct {
    NSMutableData *addrStructData = [[NSMutableData alloc] initWithLength:sizeof(struct sockaddr_in)];
    
    struct sockaddr_in *addrStruct = [addrStructData mutableBytes];
    addrStruct->sin_len = sizeof(struct sockaddr_in);
    addrStruct->sin_family = AF_INET;
    addrStruct->sin_port = htons(self.gatewayPort);
    addrStruct->sin_addr.s_addr = inet_addr([self.gatewayAddr cStringUsingEncoding:NSUTF8StringEncoding]);

    return [NSData dataWithData:addrStructData];
}

- (NSData *) constructLocalAddrStruct  {
    NSMutableData *addrStructData = [[NSMutableData alloc] initWithLength:sizeof(struct sockaddr_in)];
    
    struct sockaddr_in *addrStruct = [addrStructData mutableBytes];
    addrStruct->sin_len = sizeof(struct sockaddr_in);
    addrStruct->sin_family = AF_INET;
    addrStruct->sin_port = htons(self.repeaterPort);
    addrStruct->sin_addr.s_addr = INADDR_ANY;

    return [NSData dataWithData:addrStructData];
}

- (void) processPacket:(struct gatewayPacket *)packet {
    
    if(strncmp(packet->magic, "DSRP", 4) != 0) {
        NSLog(@"Bad packet magic: %c%c%c%c\n", packet->magic[0], packet->magic[1], packet->magic[2], packet->magic[3]);
        return;
    }
    
    switch(packet->packetType) {
        case 0x00: {
            NSDictionary *infoDict = @{ @"local": [[NSString alloc] initWithBytes:packet->payload.networkText.local
                                                                           length:sizeof(packet->payload.networkText.local)
                                                                         encoding:NSUTF8StringEncoding],
                                        @"reflector": [[NSString alloc] initWithBytes:packet->payload.networkText.reflector
                                                                               length:sizeof(packet->payload.networkText.reflector)
                                                                             encoding:NSUTF8StringEncoding],
                                        @"status": [NSData dataWithBytes:&packet->payload.networkText.status length:1] };
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:BTRRepeaterInfoReceived object:self userInfo:infoDict];
            });

            NSLog(@"Status = 0x%02X", packet->payload.networkText.status);
            break;
        }
        case 0x01:
            NSLog(@"Packet is NETWORK_TEMPTEXT\n");
            break;
        case 0x04:
            NSLog(@"Packet is NETWORK_STATUS\n");
            break;
        case GW_PACKET_TYPE_HEADER: {
            if(self.rxStreamId != 0 && self.rxStreamId != packet->payload.dstarHeader.streamId) {
                NSLog(@"Stream ID Mismatch on Header");
                return;
            }
            
            self.lastPacketTime = CFAbsoluteTimeGetCurrent();
            
            NSMutableDictionary *header = [[NSMutableDictionary alloc] init];
            header[@"myCall"] = [[NSString alloc] initWithBytes:packet->payload.dstarHeader.myCall
                                                         length:sizeof(packet->payload.dstarHeader.myCall)
                                                       encoding:NSUTF8StringEncoding];
            header[@"myCall2"] = [[NSString alloc] initWithBytes:packet->payload.dstarHeader.myCall2
                                                          length:sizeof(packet->payload.dstarHeader.myCall2)
                                                        encoding:NSUTF8StringEncoding];
            header[@"urCall"] = [[NSString alloc] initWithBytes:packet->payload.dstarHeader.urCall
                                                          length:sizeof(packet->payload.dstarHeader.urCall)
                                                        encoding:NSUTF8StringEncoding];
            header[@"rpt1Call"] = [[NSString alloc] initWithBytes:packet->payload.dstarHeader.rpt1Call
                                                           length:sizeof(packet->payload.dstarHeader.rpt1Call)
                                                         encoding:NSUTF8StringEncoding];
            header[@"rpt2Call"] = [[NSString alloc] initWithBytes:packet->payload.dstarHeader.rpt2Call
                                                           length:sizeof(packet->payload.dstarHeader.rpt2Call)
                                                         encoding:NSUTF8StringEncoding];
            header[@"streamId"] = [NSNumber numberWithUnsignedInteger:self.rxStreamId];
            header[@"time"] = [NSDate date];
            header[@"message"] = @"";
            
            if(self.rxStreamId == 0) {
                self.rxStreamId = packet->payload.dstarHeader.streamId;
                header[@"streamId"] = [NSNumber numberWithUnsignedInteger:self.rxStreamId];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName: BTRNetworkStreamStart
                                                                        object: self
                                                                      userInfo: header
                     ];
                });
                dispatch_resume(watchdogTimerSource);
                
                NSLog(@"New stream %lu: My: %@/%@ Ur: %@ RPT1: %@ RPT2: %@\n", (unsigned long) self.rxStreamId, header[@"myCall"], header[@"myCall2"], header[@"urCall"], header[@"rpt1Call"], header[@"rpt2Call"]);
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName: BTRNetworkHeaderReceived
                                                                    object: self
                                                                  userInfo: header];
            });

        }
            break;
        case GW_PACKET_TYPE_DATA: {
           if(self.rxStreamId != packet->payload.dstarData.streamId) {
               return;
            }
            
            self.lastPacketTime = CFAbsoluteTimeGetCurrent();
            
            if(packet->payload.dstarData.slowData[0] == 0x55 &&
               packet->payload.dstarData.slowData[1] == 0x2D &&
               packet->payload.dstarData.slowData[2] == 0x16) {
                if(packet->payload.dstarData.sequence != 0)
                    NSLog(@"Sync in wrong place");
            }
            
            if(packet->payload.dstarData.sequence & 0x40) {
                NSLog(@"End stream %d\n", packet->payload.dstarData.streamId);
                [self terminateIncomingStream];
                packet->payload.dstarData.sequence &= ~0x40;                
            }
            
            if(packet->payload.dstarData.sequence != rxSequence) {
                //  If the packet is more recent, reset the sequence, if not, wait for my next packet
                if(isSequenceAhead(packet->payload.dstarData.sequence, rxSequence, 21)) {
                    NSLog(@"Skipped packet: incoming %u, sequence = %u",packet->payload.dstarData.sequence, rxSequence);
                    rxSequence = packet->payload.dstarData.sequence;
                } else {
                    NSLog(@"Out of order packet: incoming = %u, sequence = %u\n", packet->payload.dstarData.sequence, rxSequence);
                    return;
                }
            }
            
            [self.slowData addData:packet->payload.dstarData.slowData streamId:self.rxStreamId];
            
            if(self.rxStreamId == 0)
                rxSequence = 0;
            else
                rxSequence = (rxSequence + 1) % 21;
            
            //  If streamId == 0, we are on the last packet of this stream.
            [self.vocoder decodeData: packet->payload.dstarData.ambeData lastPacket:(self.rxStreamId == 0)];
            break;
        }
        case 0x24:
            NSLog(@"Packet is DD Data\n");
            break;
        default:
            NSLog(@"Unknown packet type: %02x\n", packet->packetType);
            break;
    }
}

- (void) dealloc {
    // free(incomingPacket);
}

@end

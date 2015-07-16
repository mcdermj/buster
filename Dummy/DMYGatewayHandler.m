//
//  DMYGatewayHandler.m
//  Dummy
//
//  Created by Jeremy McDermond on 7/10/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "DMYGatewayHandler.h"

#import <arpa/inet.h>

#import <sys/ioctl.h>

// #define NSLog(x...)

NSString * const DMYNetworkHeaderReceived = @"DMYNetworkHeaderReceived";
NSString * const DMYNetworkStreamEnd = @"DMYNetworkStreamEnd";
NSString * const DMYNetworkStreamStart = @"DMYNetworkStreamStart";

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
        uint8 pollText[255];
        // uint8 junk[1500];  // This should go away once all packets are accounted for.
    } payload;
} __attribute__((packed));

static const struct gatewayPacket pollPacket = {
    .magic ="DSRP",
    .packetType = 0x0A,
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

@interface DMYGatewayHandler () {
    int gatewaySocket;
    dispatch_source_t dispatchSource;
    dispatch_source_t pollTimerSource;
    uint16 streamId;
    uint8 sequence;
    BOOL running;
    NSThread *readThread;
    struct gatewayPacket *incomingPacket;
    CFAbsoluteTime lastPacketTime;
}

- (NSData *) constructRemoteAddrStruct;
- (NSData *) constructLocalAddrStruct;
- (void) processPacket;
- (uint16) calculateChecksum:(struct gatewayPacket)packet;

@end

@implementation DMYGatewayHandler

@synthesize remoteAddress;
@synthesize remotePort;
@synthesize localPort;
@synthesize urCall;
@synthesize myCall;
@synthesize rpt1Call;
@synthesize rpt2Call;
@synthesize myCall2;
@synthesize vocoder;
@synthesize xmitRepeater;
@synthesize xmitMyCall;
@synthesize xmitUrCall;

#pragma mark - Initializers

- (id) initWithRemoteAddress:(NSString *)_remoteAddress remotePort:(NSUInteger)_remotePort localPort:(NSUInteger)_localPort {
    self = [super init];
    
    if(self) {
        gatewaySocket = 0;
        streamId = 0;
        
        self.remotePort = _remotePort;
        self.localPort = _localPort;
        self.remoteAddress = [NSString stringWithString:_remoteAddress];
        self.vocoder = nil;
        
        urCall = @"";
        myCall = @"";
        rpt1Call = @"";
        rpt2Call = @"";
        myCall2 = @"";
        xmitMyCall = @"";
        xmitUrCall = @"";
        xmitRepeater = @"";
        
        incomingPacket = malloc(sizeof(struct gatewayPacket));
    }
    
    return self;
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
    }
    
    if(fcntl(gatewaySocket, F_SETFL, O_NONBLOCK) == -1) {
        NSLog(@"Couldn't set socket to nonblocking: %s\n", strerror(errno));
    }
    
    NSData *addr = [self constructLocalAddrStruct];
    if(bind(gatewaySocket, (const struct sockaddr *) [addr bytes], (socklen_t) [addr length])) {
        NSLog(@"Couldn't bind gateway socket: %s\n", strerror(errno));
    }
    
    dispatch_queue_t mainQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) gatewaySocket, 0, mainQueue);
    DMYGatewayHandler __weak *weakSelf = self;
    dispatch_source_set_event_handler(dispatchSource, ^{
        [weakSelf processPacket];
    });
    
    dispatch_source_set_cancel_handler(dispatchSource, ^{ close(gatewaySocket); });
    
    dispatch_resume(dispatchSource);
    
    //  XXX Should set up a timer here for the poll interval.
    //  XXX This should eventually be put on the read serial queue.
    pollTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_timer(pollTimerSource, dispatch_walltime(NULL, 0), 60ull * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);
    NSData *pollAddr = [self constructRemoteAddrStruct];
    dispatch_source_set_event_handler(pollTimerSource, ^{
        NSLog(@"Sending Poll\n");
        if(sendto(gatewaySocket, &pollPacket, sizeof(pollPacket), 0, [pollAddr bytes], (socklen_t) [pollAddr length]) == -1) {
            NSLog(@"Couldn't send poll packet: %s\n", strerror(errno));
            return;
        }

    });
    dispatch_resume(pollTimerSource);
    
    //  XXX And for a watchdog timer
    
    NSLog(@"Completed socket setup\n");
    
    return YES;
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
        // NSLog(@"Data = %c(0x%02X) CRC = 0x%04x\n", *packetPointer, *packetPointer, crc);
    }
    
    crc = ~crc;
    
    return ((uint16) crc);
}

- (void) linkTo:(NSString *)reflector {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct gatewayPacket packet;
        short linkStreamId;
        
        memset(&packet, 0, sizeof(packet));
        
        NSData *addr = [self constructRemoteAddrStruct];
        
        NSMutableString *linkCmd = [NSMutableString stringWithString:reflector];
        [linkCmd deleteCharactersInRange:NSMakeRange(6, 1)];
        [linkCmd appendString:@"L"];
        NSLog(@"Linking to %@ with link command %@\n", reflector, linkCmd);
        strncpy((char *) packet.payload.dstarHeader.urCall, [linkCmd cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.payload.dstarHeader.urCall));
  
        // XXX This is generic code that should be constructed for whenever we need a header packet.
        // XXX Maybe a fillHeader function
        memcpy(&packet.magic, "DSRP", sizeof(packet.magic));
        packet.packetType = 0x20;
        strncpy((char *) packet.payload.dstarHeader.myCall, [xmitMyCall cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.payload.dstarHeader.myCall));
       
        NSMutableString *gateway = [NSMutableString stringWithString:xmitRepeater];
        [gateway replaceCharactersInRange:NSMakeRange(7, 1) withString:@"G"];
        NSLog(@"%@/%@\n", xmitRepeater, gateway);
        
        strncpy((char *) packet.payload.dstarHeader.rpt2Call, [xmitRepeater cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.payload.dstarHeader.rpt1Call));
        strncpy((char *) packet.payload.dstarHeader.rpt1Call, [gateway cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.payload.dstarHeader.rpt2Call));
        
        strncpy((char *) packet.payload.dstarHeader.myCall2, "HOME", sizeof(packet.payload.dstarHeader.myCall2));
        
        linkStreamId = htons((short) random());
        packet.payload.dstarHeader.streamId = linkStreamId;
        
        packet.payload.dstarHeader.checksum = [self calculateChecksum:packet];
        NSLog(@"Checksum is %x\n", packet.payload.dstarHeader.checksum);
        
        //   XXX Maybe the length should be shorter here
        size_t packetLen = sizeof(packet.magic) + sizeof(packet.packetType) + sizeof(packet.payload.dstarHeader);
        NSLog(@"packetLen = %lu\n", packetLen);
        if(sendto(gatewaySocket, &packet, packetLen, 0, [addr bytes], (socklen_t) [addr length]) == -1) {
            NSLog(@"Couldn't send link header: %s\n", strerror(errno));
            return;
        }
        
        //  Send the end stream packet
        memset(&packet.payload, 0, sizeof(packet.payload));
        packet.payload.dstarData.sequence = 0x40;
        packet.payload.dstarData.streamId = linkStreamId;
        packet.packetType = 0x21;
        packetLen = sizeof(packet.magic) + sizeof(packet.packetType) + sizeof(packet.payload.dstarData);
        if(sendto(gatewaySocket, &packet, packetLen, 0, [addr bytes], (socklen_t) [addr length]) == -1) {
            NSLog(@"Couldn't send link header: %s\n", strerror(errno));
            return;
        }

    });
}

#pragma mark - Internal Methods

- (NSData *) constructRemoteAddrStruct {
    NSMutableData *addrStructData = [[NSMutableData alloc] initWithLength:sizeof(struct sockaddr_in)];
    
    struct sockaddr_in *addrStruct = [addrStructData mutableBytes];
    addrStruct->sin_len = sizeof(struct sockaddr_in);
    addrStruct->sin_family = AF_INET;
    addrStruct->sin_port = htons(remotePort);
    addrStruct->sin_addr.s_addr = inet_addr([remoteAddress cStringUsingEncoding:NSUTF8StringEncoding]);

    return [NSData dataWithData:addrStructData];
}

- (NSData *) constructLocalAddrStruct  {
    NSMutableData *addrStructData = [[NSMutableData alloc] initWithLength:sizeof(struct sockaddr_in)];
    
    struct sockaddr_in *addrStruct = [addrStructData mutableBytes];
    addrStruct->sin_len = sizeof(struct sockaddr_in);
    addrStruct->sin_family = AF_INET;
    addrStruct->sin_port = htons(localPort);
    addrStruct->sin_addr.s_addr = INADDR_ANY;

    return [NSData dataWithData:addrStructData];
}

- (void) processPacket {
    struct sockaddr_in incomingAddress;
    socklen_t incomingAddressLen;
    
    ssize_t bytesRead = recvfrom(gatewaySocket, incomingPacket, sizeof(struct gatewayPacket), 0, (struct sockaddr *) &incomingAddress, &incomingAddressLen);
    
    if(bytesRead == -1) {
        NSLog(@"Couldn't read packet: %s\n", strerror(errno));
        return;
    }
    
    if(strncmp(incomingPacket->magic, "DSRP", 4) != 0) {
        NSLog(@"Bad packet magic: %c%c%c%c\n", incomingPacket->magic[0], incomingPacket->magic[1], incomingPacket->magic[2], incomingPacket->magic[3]);
        return;
    }
    
    __weak DMYGatewayHandler *weakSelf = self;
    
    switch(incomingPacket->packetType) {
        case 0x00:
            NSLog(@"Packet is NETWORK_TEXT\n");
            break;
        case 0x01:
            NSLog(@"Packet is NETWORK_TEMPTEXT\n");
            break;
        case 0x04:
            NSLog(@"Packet is NETWORK_STATUS\n");
            break;
        case 0x20: {
            myCall = [[NSString alloc] initWithBytes:incomingPacket->payload.dstarHeader.myCall
                                              length:sizeof(incomingPacket->payload.dstarHeader.myCall)
                                            encoding:NSUTF8StringEncoding];
            urCall = [[NSString alloc] initWithBytes:incomingPacket->payload.dstarHeader.urCall
                                              length:sizeof(incomingPacket->payload.dstarHeader.urCall)
                                            encoding:NSUTF8StringEncoding];
            rpt1Call = [[NSString alloc] initWithBytes:incomingPacket->payload.dstarHeader.rpt1Call
                                                length:sizeof(incomingPacket->payload.dstarHeader.rpt1Call)
                                              encoding:NSUTF8StringEncoding];
            rpt2Call = [[NSString alloc] initWithBytes:incomingPacket->payload.dstarHeader.rpt2Call
                                                length:sizeof(incomingPacket->payload.dstarHeader.rpt2Call)
                                              encoding:NSUTF8StringEncoding];
            myCall2 = [[NSString alloc] initWithBytes:incomingPacket->payload.dstarHeader.myCall2
                                               length:sizeof(incomingPacket->payload.dstarHeader.myCall2)
                                             encoding:NSUTF8StringEncoding];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName: DMYNetworkHeaderReceived
                                                                    object: weakSelf
                                                                  userInfo: nil];
            });
            //NSLog(@"My = %@/%@\n", myCall, myCall2);
            //NSLog(@"UR = %@\n", urCall);
            //NSLog(@"RPT1 = %@\n", rpt1Call);
            //NSLog(@"RPT2 = %@\n", rpt2Call);
        }
            break;
        case 0x21:
            if(streamId == 0) {
                streamId = incomingPacket->payload.dstarData.streamId;
                sequence = incomingPacket->payload.dstarData.sequence;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName: DMYNetworkStreamStart
                                                                        object: weakSelf
                                                                      userInfo: nil];
                });
                
                NSLog(@"New incoming stream with ID %d\n", streamId);
            }
            
            if(streamId != incomingPacket->payload.dstarData.streamId) {
                //NSLog(@"Stream ID mismatch\n");
                //  If we have missed time for about 10 packets, this stream is probably over and we missed the end packet.
                //  XXX This should probably be in a watchdog timer somehow.
                if(CFAbsoluteTimeGetCurrent() > lastPacketTime + .200) {
                    NSLog(@"Stream timed out\n");
                    streamId = 0;
                    [[NSNotificationCenter defaultCenter] postNotificationName: DMYNetworkStreamEnd
                                                                        object: self
                                                                      userInfo: nil];
                }
                return;
            }
            
            lastPacketTime = CFAbsoluteTimeGetCurrent();
            
            if(incomingPacket->payload.dstarData.slowData[0] == 0x55 &&
               incomingPacket->payload.dstarData.slowData[1] == 0x2D &&
               incomingPacket->payload.dstarData.slowData[2] == 0x16) {
                //NSLog(@"Received Sync Packet\n");
                // sequence = 0;
                if(incomingPacket->payload.dstarData.sequence != 0)
                    NSLog(@"Sync in wrong place");
            }
            
            if(incomingPacket->payload.dstarData.sequence & 0x40) {
                NSLog(@"End of stream %d\n", incomingPacket->payload.dstarData.streamId);
                streamId = 0;
                incomingPacket->payload.dstarData.sequence &= ~0x40;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName: DMYNetworkStreamEnd
                                                                        object: weakSelf
                                                                      userInfo: nil];
                });
            }
            
            if(incomingPacket->payload.dstarData.sequence != sequence) {
                //  If the packet is more recent, reset the sequence, if not, wait for my next packet
                if(isSequenceAhead(incomingPacket->payload.dstarData.sequence, sequence, 20))
                    sequence = incomingPacket->payload.dstarData.sequence;
                else {
                    NSLog(@"Out of order packet: incoming = %u, sequence = %u\n", incomingPacket->payload.dstarData.sequence, sequence);
                    return;
                }
            }
            
            sequence = (sequence + 1) % 21;
            
            [vocoder decodeData: incomingPacket->payload.dstarData.ambeData];
            break;
        case 0x24:
            NSLog(@"Packet is DD Data\n");
            break;
        default:
            NSLog(@"Unknown packet type: %02x\n", incomingPacket->packetType);
            break;
    }
}

- (void) dealloc {
    NSLog(@"Deallocing Gateway Handler\n");
    free(incomingPacket);
}

@end

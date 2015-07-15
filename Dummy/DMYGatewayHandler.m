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
        // uint8 junk[1500];  // This should go away once all packets are accounted for.
    } payload;
} __attribute__((packed));

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
    
    dispatch_queue_t mainQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) gatewaySocket, 0, mainQueue);
    DMYGatewayHandler __weak *weakSelf = self;
    dispatch_source_set_event_handler(dispatchSource, ^{
        [weakSelf processPacket];
    });
    
    dispatch_source_set_cancel_handler(dispatchSource, ^{ close(gatewaySocket); });
    
    dispatch_resume(dispatchSource);
    
    //  XXX Should set up a timer here for the poll interval.
    //  XXX And for a watchdog timer
    
    NSLog(@"Completed socket setup\n");
    
    return YES;
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
            //NSLog(@"Packet is NETWORK_HEADER\n");
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
            //NSLog(@"Packet is NETWORK_DATA\n");
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
                NSLog(@"Stream ID mismatch\n");
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
        
            [vocoder decodeData:[NSData dataWithBytes:incomingPacket->payload.dstarData.ambeData length:sizeof(incomingPacket->payload.dstarData.ambeData)]];
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

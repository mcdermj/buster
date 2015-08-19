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

static const char DPLUS_TYPE_POLL = 0x00;
static const char DPLUS_TYPE_LINK = 0x18;
static const char DPLUS_TYPE_LINKMODULE = 0x04;

static const char DPLUS_END_PATTERN[] = { 0x55, 0x55, 0x55, 0x55, 0xC8, 0x7A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
static const char DPLUS_NULL_PATTERN[] = { 0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8 };

static const struct dplus_packet linkModuleTemplate = {
    .length = 0xC01C,
    .link.type = DPLUS_TYPE_LINKMODULE,
    .link.padding = 0x00,
    .link.module.repeater = "    ",
    .link.module.magic = "DV019999"
};

static const struct dplus_packet headerTemplate = {
    .length = 0x803A,
    .data.header.magic = "DSVT",
    .data.header.type = 0x10,
    .data.header.unknown = { 0x00, 0x00, 0x00, 0x20 },
    .data.header.band = { 0x00, 0x02, 0x01 },
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
    .data.header.band = { 0x00, 0x02, 0x01 },
    .data.header.id = 0,
    .data.header.sequence = 0,
    .data.ambeData.voice = { 0 },
    .data.ambeData.data = { 0 },
    .data.ambeData.endPattern = { 0 }
};


@interface BTRDPlusLink ()
@property (readonly, nonatomic) NSData *unlinkPacket;
@property (readonly, nonatomic) NSData *pollPacket;
@property (readonly, nonatomic) NSData *linkPacket;

@end

@implementation BTRDPlusLink

- (id) init {
    self = [super initWithPort:20001 packetSize:sizeof(struct dplus_packet)];
    if(self) {
        struct dplus_packet unlinkPacket = {
            .length = 0x05,
            .link.type = DPLUS_TYPE_LINK,
            .link.padding = 0x00,
            .link.state = 0x00
        };
        _unlinkPacket = [NSData dataWithBytes:&unlinkPacket length:dplus_packet_size(unlinkPacket)];
        
        struct dplus_packet pollPacket = {
            .length = 0x6003,
            .link.type = DPLUS_TYPE_POLL
        };
        _pollPacket = [NSData dataWithBytes:&pollPacket length:dplus_packet_size(pollPacket)];
        
        struct dplus_packet linkPacket = {
            .length = 0x05,
            .link.type = DPLUS_TYPE_LINK,
            .link.padding = 0x00,
            .link.state = 0x01
        };
        _linkPacket = [NSData dataWithBytes:&linkPacket length:dplus_packet_size(linkPacket)];

    }
    
    return self;
}

-(void)sendPoll {
    [self sendPacket:self.pollPacket];
}

-(void)sendUnlink {
    [self sendPacket:self.unlinkPacket];
}

-(void)sendLink {
    [self sendPacket:self.linkPacket];
}

-(NSString *)getAddressForReflector:(NSString *)reflector {
    NSUInteger reflectorIndex = [[BTRDPlusAuthenticator sharedInstance].reflectorList indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [obj[@"name"] isEqualToString:reflector];
    }];
    
    if(reflectorIndex == NSNotFound)
        return nil;
    
    return [BTRDPlusAuthenticator sharedInstance].reflectorList[reflectorIndex][@"address"];
}

-(void)processPacket:(void *)data {
    struct dplus_packet *incomingPacket = (struct dplus_packet *)data;
    
    switch(incomingPacket->length & 0xF000) {
        case 0x8000:
            if(strncmp(incomingPacket->data.header.magic, "DSVT", 4)) {
                NSLog(@"Invalid magic on a DPlus data packet: %s", incomingPacket->data.header.magic);
                return;
            }
            [self processDataPacket:incomingPacket];
            break;
        case 0x6000:
            //  Poll packet, can ignore because the link last packet time is set in the superclass.
            break;
        case 0xC000:
        case 0x0000:
            [self processLinkPacket:incomingPacket];
            break;
        default:
            NSLog(@"Invalid flag byte 0x%02X", incomingPacket->length & 0xF000);
            break;
    }

}

- (void)processLinkPacket:(struct dplus_packet *)packet {
    switch(packet->link.type) {
        case DPLUS_TYPE_LINK:
            switch(packet->link.state) {
                case 0x00:
                    NSLog(@"DPlus reports unlinked");
                    self.linkState = UNLINKED;
                    break;
                case 0x01: {
                    NSLog(@"DPlus reports linked");
                    self.linkState = LINKING;
                    NSMutableData *linkPacket = [NSMutableData dataWithBytes:&linkModuleTemplate length:dplus_packet_size(linkModuleTemplate)];
                
                    memcpy(((struct dplus_packet *) linkPacket.bytes)->link.module.repeater, [[BTRDPlusAuthenticator sharedInstance].authCall cStringUsingEncoding:NSUTF8StringEncoding], [BTRDPlusAuthenticator sharedInstance].authCall.length);
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
                NSLog(@"Received ACK from repeater, we are now linked");
                self.linkState = LINKED;
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

-(void) sendAMBE:(void *)data lastPacket:(BOOL)last {
    if(self.linkState != LINKED)
        return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        struct dplus_packet packet = {};
        
        //  If the sequence is 0, send a header packet.
        if(self.txSequence == 0) {
            NSLog(@"Sending header for stream %hu", self.txStreamId);
            memcpy(&packet, &headerTemplate, sizeof(struct dplus_packet));
            
            packet.data.header.id = self.txStreamId;
            
            //  XXX This should get the global value
            strncpy(packet.data.headerData.myCall, [[[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"] stringByPaddingToLength:8 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.headerData.myCall));
            strncpy(packet.data.headerData.myCall2, [[[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall2"] stringByPaddingToLength:4 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.headerData.myCall2));
            
            // NSString *rpt1Call = [NSString stringWithFormat:@"%@ D", [[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"] stringByPaddingToLength:6 withString:@" " startingAtIndex:0]];
            strncpy(packet.data.headerData.rpt1Call, [[[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"] stringByPaddingToLength:8 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.headerData.rpt1Call));
            
            strncpy(packet.data.headerData.rpt2Call, [[self.linkTarget stringByPaddingToLength:8 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.headerData.rpt2Call));

            packet.data.headerData.sum = [self calculateChecksum:&packet.data.headerData.flags length:(sizeof(packet.data.headerData.myCall) * 4) +
                                        sizeof(packet.data.headerData.myCall2) +
                                        sizeof(packet.data.headerData.flags)];
            
            [self sendPacket:[NSData dataWithBytes:&packet length:dplus_packet_size(packet)]];
        }
        
        memcpy(&packet, &ambeTemplate, sizeof(struct dplus_packet));
        packet.data.header.sequence = self.txSequence;
        packet.data.header.id = self.txStreamId;
        memcpy(&packet.data.ambeData.voice, data, sizeof(packet.data.ambeData.voice));
        memcpy(&packet.data.ambeData.data, [[BTRDataEngine sharedInstance].slowData getDataForSequence:self.txSequence], sizeof(packet.data.ambeData.data));
        
        if(last) {
            self.txSequence = 0;
            self.txStreamId = (short) random();
            packet.data.header.sequence |= 0x40;
            packet.length = 0x8020;
            memcpy(&packet.data.ambeData.endPattern, DPLUS_END_PATTERN, sizeof(packet.data.ambeData.endPattern));
            memcpy(&packet.data.ambeData.voice, DPLUS_NULL_PATTERN, sizeof(packet.data.ambeData.voice));
        } else {
            self.txSequence = (self.txSequence + 1) % 21;
        }
        
        [self sendPacket:[NSData dataWithBytes:&packet length:dplus_packet_size(packet)]];
    });
}



@end

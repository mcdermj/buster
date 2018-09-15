//
//  BTRDPlusLink.m
//
//  Copyright (c) 2015 - Annaliese C. McDermond (NH6Z)

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
#import "BTRDataEngine.h"
#import "BTRSlowDataCoder.h"
#import "BTRIRCDDBGateways.h"

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
        struct dstar_frame frame;
    };
};
#pragma pack(pop)

#define dplus_packet_size(a) ((a).length & 0x0FFF)

static const char DPLUS_TYPE_POLL = 0x00;
static const char DPLUS_TYPE_LINK = 0x18;
static const char DPLUS_TYPE_LINKMODULE = 0x04;

static const char DPLUS_END_PATTERN[] = { 0x55, 0x55, 0x55, 0x55, 0xC8, 0x7A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

static const struct dplus_packet linkModuleTemplate = {
    .length = 0xC01C,
    .link.type = DPLUS_TYPE_LINKMODULE,
    .link.padding = 0x00,
    .link.module.repeater = "    ",
    .link.module.magic = "DV019999"
};

@interface BTRDPlusLink ()
@property (readonly, nonatomic) NSData *unlinkPacket;
@property (readonly, nonatomic) NSData *pollPacket;
@property (readonly, nonatomic) NSData *linkPacket;
@property (readonly, nonatomic) BTRDPlusAuthenticator *authenticator;
@property (readonly, nonatomic) BTRIRCDDBGateways *ircDDBGateways;
@end

@implementation BTRDPlusLink


+(void) load {
    [BTRDataEngine registerLinkDriver:self];
}

- (id) init {
    self = [super init];
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
        
        _authenticator = [[BTRDPlusAuthenticator alloc] init];
        _ircDDBGateways = [[BTRIRCDDBGateways alloc] init];

    }
    
    return self;
}

-(BOOL)canHandleLinkTo:(NSString*)linkTarget {
    if(linkTarget.length != 8)
        return NO;
    
    if(self.authenticator.reflectorList[linkTarget.callWithoutModule])
        return YES;
    
    //  The ircDDB enabled gateways should support DPlus.
    if(self.ircDDBGateways.gateways[linkTarget.callWithoutModule])
        return YES;
    
    return NO;
}

-(NSArray<NSString *> *)destinations {
    NSMutableArray *destinations = [[NSMutableArray alloc] initWithArray:self.authenticator.reflectorList.allKeys];
    [destinations addObjectsFromArray:self.ircDDBGateways.gateways.allKeys];
    
    return destinations;
}

-(CFAbsoluteTime)pollInterval {
    return 1.0;
}

-(unsigned short)clientPort {
    return 0;
}

-(unsigned short)serverPort {
    return 20001;
}

-(size_t)packetSize {
    return sizeof(struct dplus_packet);
}

-(BOOL)hasReliableChecksum {
    return NO;
}

-(void)sendPoll {
    [self sendPacket:self.pollPacket];
}

-(void)sendUnlink {
    [self sendPacket:self.unlinkPacket];
}

-(void)sendLink {
    NSLog(@"Sending DPLus link packet");
    [self sendPacket:self.linkPacket];
}

-(NSString *)getAddressForReflector:(NSString *)reflector {
    NSString *reflectorAddress = self.authenticator.reflectorList[reflector];
    if(reflectorAddress)
        return reflectorAddress;
    
    //  The ircDDB enabled gateways should support DPlus.
    return self.ircDDBGateways.gateways[reflector];
}

-(void)processPacket:(NSData *)data {
    struct dplus_packet *incomingPacket = (struct dplus_packet *)data.bytes;
    
    switch(incomingPacket->length & 0xF000) {
        case 0x8000:
            if(strncmp(incomingPacket->frame.magic, "DSVT", 4)) {
                NSLog(@"Invalid magic on a DPlus data packet: %s", incomingPacket->frame.magic);
                return;
            }
            
            [self processFrame:&incomingPacket->frame];
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
                    if(self.linkState != CONNECTED)
                        return;
                    
                    NSLog(@"DPlus reports linked");
                    self.linkState = LINKING;
                    NSMutableData *linkPacket = [NSMutableData dataWithBytes:&linkModuleTemplate length:dplus_packet_size(linkModuleTemplate)];
                
                    memcpy(((struct dplus_packet *) linkPacket.mutableBytes)->link.module.repeater, self.authenticator.authCall.UTF8String, self.authenticator.authCall.length);
                    [self sendPacket:linkPacket];
                    break;
                }
                default:
                    NSLog(@"Received unknown value for link packet: 0x%02X", packet->link.state);
                    break;
            }
            break;
        case DPLUS_TYPE_LINKMODULE:
            if(self.linkState != LINKING)
                return;
            
            if(!strncmp(packet->link.module.repeater, "OKRW", 4)) {
                NSLog(@"Received ACK from repeater, we are now linked");
                self.linkState = LINKED;
            } else if(!strncmp(packet->link.module.repeater, "BUSY", 4)) {
                NSLog(@"Received NACK from repeater, link failed");
                NSError *error = [NSError errorWithDomain:@"BTRErrorDomain" code:3 userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ refused the link request", self.linkTarget]}];
                [self.delegate destinationDidError:self.linkTarget error:error];
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
            // NSLog(@"Dump: %@", [NSData dataWithBytes:packet length:sizeof(struct dplus_packet)]);
            break;
    }
}

-(void)sendFrame:(struct dstar_frame *)frame {
    struct dplus_packet packet = { 0 };
    
    memcpy(&packet.frame, frame, sizeof(packet.frame));
    switch(frame->type) {
        case 0x20:
            if(frame->sequence & 0x40) {
                packet.length = 0x8020;
                memcpy(&frame->ambe.endPattern, DPLUS_END_PATTERN, sizeof(DPLUS_END_PATTERN));
            } else {
                packet.length = 0x801D;
            }
            break;
        case 0x10:
            packet.length = 0x803A;
            break;
        default:
            NSLog(@"Unknown packet type");
            return;
    }
    [self sendPacket:[NSData dataWithBytes:&packet length:dplus_packet_size(packet)]];
}

@end

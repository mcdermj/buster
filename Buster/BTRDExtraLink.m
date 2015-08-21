//
//  BTRDExtraLink.m
//  Buster
//
//  Created by Jeremy McDermond on 8/19/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "BTRDExtraLink.h"

#import "BTRGatewayHandler.h"
#import "BTRDataEngine.h"
#import "BTRSlowDataCoder.h"

#pragma pack(push, 1)
struct dextra_packet {
    union {
        struct {
            char callsign[8];
            char module;
            char reflectorModule;
            char response[3];
            char terminator;
        } link;
        struct dstar_frame frame;
    };
};
#pragma pack(pop)

static const struct dextra_packet linkTemplate = {
    .link.callsign = "        ",
    .link.module = ' ',
    .link.reflectorModule = ' ',
    .link.response[0] = 0x00
};

static NSDictionary *_reflectorList;

@interface BTRDExtraLink ()

+(NSDictionary *)reflectorList;

@end

@implementation BTRDExtraLink

+(NSDictionary *) reflectorList {
    if(!_reflectorList)
        _reflectorList = [NSDictionary dictionaryWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"DExtraReflectors" withExtension:@"plist"]];
    
    return _reflectorList;
}

+(BOOL)canHandleLinkTo:(NSString*)linkTarget {
    NSString *reflector = [[linkTarget substringWithRange:NSMakeRange(0, 7)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if([BTRDExtraLink reflectorList][reflector])
        return YES;
    
    return NO;
}

+(void) load {
    [BTRDataEngine registerLinkDriver:self];
}

-(id) initWithLinkTo:(NSString *)linkTarget {
    self = [super initWithLinkTo:linkTarget];
    if (self) {
    }
    return self;
}

-(CFAbsoluteTime)pollInterval {
    return 5.0;
}

-(unsigned short)clientPort {
    return 30001;
}

-(unsigned short)serverPort {
    return 30001;
}

-(size_t)packetSize {
    return sizeof(struct dextra_packet);
}


-(void)processPacket:(NSData *)packetData {
    struct dextra_packet *packet = (struct dextra_packet *) packetData.bytes;
    
    if(!strncmp(packet->frame.magic, "DSVT", 4)) {
        [self processFrame:&packet->frame];
        NSLog(@"Got data packet");
    } else {
        NSLog(@"Got link packet");
        // XXX This check is broken!  It needs to be *EITHER* the reflector call, *OR* our call.
        // NSString *target = [[self.linkTarget substringWithRange:NSMakeRange(0, 7)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        /* if(![self.linkTarget.callWithoutModule isEqualToString:[NSString stringWithCallsign:&(packet->link.callsign)]]) {
            NSLog(@"Packet doesn't come from expected reflector: %@", [NSString stringWithCallsign:&(packet->link.callsign)]);
            NSLog(@"Link Target is %@", self.linkTarget);
            return;
        } */
        switch(packetData.length) {
            case 9:
                //  Poll packet.  Ignore because this is handled in the superclass.
                break;
            case 14:
                // Link acknowledgment packet
                if(!strncmp(packet->link.response, "ACK", 3)) {
                    self.linkState = LINKED;
                    NSLog(@"Got ACK, going linked");
                } else if(!strncmp(packet->link.response, "NAK", 3)) {
                    NSLog(@"Got NAK, unlinking");
                    [self unlink];
                } else
                    NSLog(@"Unknown link acknowledgment");
                break;
            default:
                NSLog(@"Unknown link packet");
                break;
        }
    }    
}

-(void)sendPoll {
    NSMutableData *pollPacket = [NSMutableData dataWithBytes:&linkTemplate length:9];
    NSString *myCall = [[[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"] stringByPaddingToLength:8 withString:@" " startingAtIndex:0] substringWithRange:NSMakeRange(0, 7)];
    memcpy(pollPacket.mutableBytes, myCall.UTF8String, 7);
    ((char *) pollPacket.mutableBytes)[8] = 0x00;
    [self sendPacket:pollPacket];
}

-(void)sendLinkPacketWithModule:(char)module {
    NSMutableData *linkPacket = [NSMutableData dataWithBytes:&linkTemplate length:11];
    struct dextra_packet *packet = (struct dextra_packet *)linkPacket.mutableBytes;
    
    NSString *myCall = [[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"] stringByPaddingToLength:8 withString:@" " startingAtIndex:0];
    NSString *callOnly = [myCall substringWithRange:NSMakeRange(0, 7)];
    
    packet->link.module = (char) [myCall characterAtIndex:7];
    packet->link.reflectorModule = module;
    memcpy(packet->link.callsign, [callOnly cStringUsingEncoding:NSUTF8StringEncoding], callOnly.length);
    
    [self sendPacket:linkPacket];
}

-(void)sendUnlink {
    [self sendLinkPacketWithModule:' '];
    self.linkState = UNLINKED;
}

-(void)sendLink {
    [self sendLinkPacketWithModule:(char) [self.linkTarget characterAtIndex:7]];
}

-(void)sendFrame:(struct dstar_frame *)frame {
    [self sendPacket:[NSData dataWithBytes:frame length:dstar_frame_size(frame)]];
}

-(NSString *)getAddressForReflector:(NSString *)reflector {
    return [NSHost hostWithName:[BTRDExtraLink reflectorList][reflector]].address;
}

@end

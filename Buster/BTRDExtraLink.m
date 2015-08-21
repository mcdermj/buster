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
        struct dstarFrame frame;
    };
};
#pragma pack(pop)

static const struct dextra_packet linkTemplate = {
    .link.callsign = "        ",
    .link.module = ' ',
    .link.reflectorModule = ' ',
    .link.response[0] = 0x00
};

static const struct dextra_packet headerTemplate = {
    .frame.magic = "DSVT",
    .frame.type = 0x10,
    .frame.unknown = { 0x00, 0x00, 0x00, 0x20 },
    .frame.band = { 0x00, 0x02, 0x01 },
    .frame.id = 0,
    .frame.sequence = 0x80,
    .frame.header.flags = { 0x00, 0x00, 0x00 },
    .frame.header.rpt2Call = "        ",
    .frame.header.rpt1Call = "        ",
    .frame.header.urCall = "        ",
    .frame.header.myCall = "        ",
    .frame.header.myCall2 = "    ",
    .frame.header.sum = 0xFFFF
};

static const struct dextra_packet ambeTemplate = {
    .frame.magic = "DSVT",
    .frame.type = 0x10,
    .frame.unknown = { 0x00, 0x00, 0x00, 0x20 },
    .frame.band = { 0x00, 0x02, 0x01 },
    .frame.id = 0,
    .frame.sequence = 0,
    .frame.ambe.voice = AMBE_NULL_PATTERN,
    .frame.ambe.data = { 0 }
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
        switch(packet->frame.type) {
            case 0x10: {
                NSDictionary *header = @{
                                         @"rpt1Call" : [NSString stringWithCallsign:packet->frame.header.rpt1Call],
                                         @"rpt2Call" : [NSString stringWithCallsign:packet->frame.header.rpt2Call],
                                         @"myCall" : [NSString stringWithCallsign:packet->frame.header.myCall],
                                         @"myCall2" : [NSString stringWithShortCallsign:packet->frame.header.myCall2],
                                         @"urCall" : [NSString stringWithCallsign:packet->frame.header.urCall],
                                         @"streamId" : [NSNumber numberWithUnsignedInteger:packet->frame.id],
                                         @"time" : [NSDate date],
                                         @"message" : @""
                                         };
                [self processHeader:header];
                break;
            }
            case 0x20:
                [self processAMBE:packet->frame.ambe.voice forId:packet->frame.id withSequence:packet->frame.sequence andData:packet->frame.ambe.data];
                break;
        }
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

-(void)sendAMBE:(void *)data lastPacket:(BOOL)last {
    if(self.linkState != LINKED)
        return;
    BTRDExtraLink __weak *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        struct dextra_packet packet = {};
        
        //  If the sequence is 0, send a header packet.
        if(weakSelf.txSequence == 0) {
            NSLog(@"Sending header for stream %hu", weakSelf.txStreamId);
            memcpy(&packet, &headerTemplate, sizeof(struct dextra_packet));
            
            packet.frame.id = weakSelf.txStreamId;
            
            //  XXX This should get the global value
            strncpy(packet.frame.header.myCall, [[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"].paddedCall.UTF8String, sizeof(packet.frame.header.myCall));
            strncpy(packet.frame.header.myCall2, [[[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall2"] stringByPaddingToLength:4 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.frame.header.myCall2));
            
            strncpy(packet.frame.header.rpt1Call, [[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"].paddedCall.UTF8String, sizeof(packet.frame.header.rpt1Call));
            
            strncpy(packet.frame.header.rpt2Call, weakSelf.linkTarget.paddedCall.UTF8String, sizeof(packet.frame.header.rpt2Call));
            
            /* packet.data.header.sum = [weakSelf calculateChecksum:&packet.data.header.flags length:(sizeof(packet.data.header.myCall) * 4) +
                                          sizeof(packet.data.header.myCall2) +
                                          sizeof(packet.data.header.flags)]; */
            packet.frame.header.sum = 0x0101;
            
            [weakSelf sendPacket:[NSData dataWithBytes:&packet length:56]];
        }
        
        memcpy(&packet, &ambeTemplate, sizeof(struct dextra_packet));
        packet.frame.sequence = weakSelf.txSequence;
        packet.frame.id = weakSelf.txStreamId;
        memcpy(&packet.frame.ambe.voice, data, sizeof(packet.frame.ambe.voice));
        
        if(last) {
            weakSelf.txSequence = 0;
            weakSelf.txStreamId = (short) random();
            packet.frame.sequence |= 0x40;
        } else {
            memcpy(&packet.frame.ambe.data, [[BTRDataEngine sharedInstance].slowData getDataForSequence:weakSelf.txSequence], sizeof(packet.frame.ambe.data));
            weakSelf.txSequence = (weakSelf.txSequence + 1) % 21;
        }
        
        [weakSelf sendPacket:[NSData dataWithBytes:&packet length:27]];
    });

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

-(NSString *)getAddressForReflector:(NSString *)reflector {
    return [NSHost hostWithName:[BTRDExtraLink reflectorList][reflector]].address;
}

@end

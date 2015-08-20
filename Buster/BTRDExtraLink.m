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
        struct {
            char magic[4];  //  "DSVT"
            char type;  //  0x20 = AMBE, 0x10 = Header
            char unknown[4]; // { 0x00, 0x00, 0x00, 0x20 }
            char band[3]; //  { 0x00, 0x02, 0x01 }
            unsigned short id;
            char sequence;
            union {
                struct {
                    char voice[9];
                    char data[3];
                } ambe;
                struct {
                    char flags[3];
                    char rpt2Call[8];
                    char rpt1Call[8];
                    char urCall[8];
                    char myCall[8];
                    char myCall2[4];
                    unsigned short sum;
                } header;
            };
        } data;
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
    .data.magic = "DSVT",
    .data.type = 0x10,
    .data.unknown = { 0x00, 0x00, 0x00, 0x20 },
    .data.band = { 0x00, 0x02, 0x01 },
    .data.id = 0,
    .data.sequence = 0x80,
    .data.header.flags = { 0x00, 0x00, 0x00 },
    .data.header.rpt2Call = "        ",
    .data.header.rpt1Call = "        ",
    .data.header.urCall = "        ",
    .data.header.myCall = "        ",
    .data.header.myCall2 = "    ",
    .data.header.sum = 0xFFFF
};

static const struct dextra_packet ambeTemplate = {
    .data.magic = "DSVT",
    .data.type = 0x10,
    .data.unknown = { 0x00, 0x00, 0x00, 0x20 },
    .data.band = { 0x00, 0x02, 0x01 },
    .data.id = 0,
    .data.sequence = 0,
    .data.ambe.voice = AMBE_NULL_PATTERN,
    .data.ambe.data = { 0 }
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
    
    if(!strncmp(packet->data.magic, "DSVT", 4)) {
        switch(packet->data.type) {
            case 0x10: {
                NSDictionary *header = @{
                                         @"rpt1Call" : call_to_nsstring(packet->data.header.rpt1Call),
                                         @"rpt2Call" : call_to_nsstring(packet->data.header.rpt2Call),
                                         @"myCall" : call_to_nsstring(packet->data.header.myCall),
                                         @"myCall2" : call_to_nsstring(packet->data.header.myCall2),
                                         @"urCall" : call_to_nsstring(packet->data.header.urCall),
                                         @"streamId" : [NSNumber numberWithUnsignedInteger:packet->data.id],
                                         @"time" : [NSDate date],
                                         @"message" : @""
                                         };
                [self processHeader:header];
                break;
            }
            case 0x20:
                [self processAMBE:packet->data.ambe.voice forId:packet->data.id withSequence:packet->data.sequence andData:packet->data.ambe.data];
                break;
        }
        NSLog(@"Got data packet");
    } else {
        NSLog(@"Got link packet");
        if([self.linkTarget isEqualToString:[[[NSString alloc] initWithBytes:packet->link.callsign length:8 encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]]) {
            NSLog(@"Packet doesn't come from expected reflector");
            return;
        }
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
            
            packet.data.id = weakSelf.txStreamId;
            
            //  XXX This should get the global value
            strncpy(packet.data.header.myCall, [[[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"] stringByPaddingToLength:8 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.header.myCall));
            strncpy(packet.data.header.myCall2, [[[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall2"] stringByPaddingToLength:4 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.header.myCall2));
            
            // NSString *rpt1Call = [NSString stringWithFormat:@"%@ D", [[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"] stringByPaddingToLength:6 withString:@" " startingAtIndex:0]];
            strncpy(packet.data.header.rpt1Call, [[[[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"] stringByPaddingToLength:8 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.header.rpt1Call));
            
            strncpy(packet.data.header.rpt2Call, [[weakSelf.linkTarget stringByPaddingToLength:8 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(packet.data.header.rpt2Call));
            
            /* packet.data.header.sum = [weakSelf calculateChecksum:&packet.data.header.flags length:(sizeof(packet.data.header.myCall) * 4) +
                                          sizeof(packet.data.header.myCall2) +
                                          sizeof(packet.data.header.flags)]; */
            packet.data.header.sum = 0x0101;
            
            [weakSelf sendPacket:[NSData dataWithBytes:&packet length:56]];
        }
        
        memcpy(&packet, &ambeTemplate, sizeof(struct dextra_packet));
        packet.data.sequence = weakSelf.txSequence;
        packet.data.id = weakSelf.txStreamId;
        memcpy(&packet.data.ambe.voice, data, sizeof(packet.data.ambe.voice));
        
        if(last) {
            weakSelf.txSequence = 0;
            weakSelf.txStreamId = (short) random();
            packet.data.sequence |= 0x40;
        } else {
            memcpy(&packet.data.ambe.data, [[BTRDataEngine sharedInstance].slowData getDataForSequence:weakSelf.txSequence], sizeof(packet.data.ambe.data));
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

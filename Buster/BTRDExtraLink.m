//
//  BTRDExtraLink.m
//  Buster
//
//  Created by Jeremy McDermond on 8/19/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "BTRDExtraLink.h"

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
    .link.module = 'A',
    .link.reflectorModule = ' ',
    .link.response[0] = 0x00
};

static NSDictionary *_reflectorList;

@interface BTRDExtraLink ()

+(NSDictionary *)reflectorList;

@end

@implementation BTRDExtraLink

+(NSDictionary *) reflectorList {
    return _reflectorList;
}


+(void) load {
    [BTRDataEngine registerLinkDriver:self];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if(!_reflectorList) {
            if ((_reflectorList = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:@"http://ar-dns.net/dextra-gw.plist"]]) == nil) {
                _reflectorList = [NSDictionary dictionaryWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"DExtraReflectors" withExtension:@"plist"]];
            }
        }
    });
}

-(NSArray<NSString *> *)destinations {
    return [[BTRDExtraLink reflectorList].allKeys copy];
}

-(BOOL)canHandleLinkTo:(NSString*)linkTarget {
    if(linkTarget.length != 8)
        return NO;
    
    if([BTRDExtraLink reflectorList][linkTarget.callWithoutModule])
        return YES;
    
    return NO;
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

-(BOOL)hasReliableChecksum {
    return YES;
}


-(void)processPacket:(NSData *)packetData {
    struct dextra_packet *packet = (struct dextra_packet *) packetData.bytes;
    
    if(!strncmp(packet->frame.magic, "DSVT", 4)) {
        [self processFrame:&packet->frame];
    } else {
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
                    NSError *error = [NSError errorWithDomain:@"BTRErrorDomain" code:3 userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ refused the link request", self.linkTarget]}];
                    [self.delegate destinationDidError:self.linkTarget error:error];
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
    NSString *myCall = [self.myCall.paddedCall substringWithRange:NSMakeRange(0, 7)];
    memcpy(pollPacket.mutableBytes, myCall.UTF8String, 7);
    ((char *) pollPacket.mutableBytes)[8] = 0x00;
    [self sendPacket:pollPacket];
}

-(void)sendLinkPacketWithModule:(char)module {
    if([self.linkTarget isEqualToString:@""])
        return;

    NSMutableData *linkPacket = [NSMutableData dataWithBytes:&linkTemplate length:11];
    struct dextra_packet *packet = (struct dextra_packet *)linkPacket.mutableBytes;
    
    //  XXX This works but is ugly.  characterAtIndex returns an unichar, and we should really
    //  XXX do some sort of real UTF8 conversion rather than just casting it down.
    //  XXX Maybe it doesn't make much of a difference since the module should only be
    //  XXX in the range of A-Z.
    NSAssert(self.rpt1Call.length == 8, @"rpt1Call is not 8 characters");
    packet->link.module = (char) [self.rpt1Call characterAtIndex:7];
    packet->link.reflectorModule = module;
    [self.rpt1Call getBytes:packet->link.callsign maxLength:sizeof(packet->link.callsign) usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, 8) remainingRange:NULL];
    
    [self sendPacket:linkPacket];
}

-(void)sendUnlink {
    [self sendLinkPacketWithModule:' '];
    self.linkState = UNLINKED;
}

-(void)sendLink {
    NSLog(@"Sending link packet");

    [self sendLinkPacketWithModule:(char) [self.linkTarget.paddedCall characterAtIndex:7]];
}

-(void)sendFrame:(struct dstar_frame *)frame {
    [self sendPacket:[NSData dataWithBytes:frame length:dstar_frame_size(frame)]];
}

-(NSString *)getAddressForReflector:(NSString *)reflector {
    return [NSHost hostWithName:[BTRDExtraLink reflectorList][reflector]].address;
}

@end

//
//  BTRDCSLink.m
//  Buster
//
//  Created by Jeremy McDermond on 10/2/15.
//  Copyright © 2015 NH6Z. All rights reserved.
//

#import "BTRDCSLink.h"

#import "BTRLinkDriverSubclass.h"
#import "BTRDataEngine.h"
#import "DStarUtils.h"

#pragma pack(push, 1)
struct dcs_packet {
    union {
        struct {
            char callsign[8];
            char module;
            char reflectorModule;
            union {
                struct {
                    char response[3];
                    char terminator;
                } response;
                struct {
                    char terminator;
                    char reflectorCall[8];
                    char htmlData[500];
                } request;
            };
        } link;
        struct dstar_frame frame;
    };
};
#pragma pack(pop)

static const struct dcs_packet linkTemplate = {
    .link.callsign = "        ",
    .link.module = 'A',
    .link.reflectorModule = ' ',
    .link.request.terminator = 0x00,
    .link.request.reflectorCall = "        ",
    .link.request.htmlData = { 0x00 }
};

static NSDictionary *_reflectorList;

@interface BTRDCSLink ()

+(NSDictionary *)reflectorList;

@end


@implementation BTRDCSLink

+(NSDictionary *) reflectorList {
    if(!_reflectorList)
        _reflectorList = [NSDictionary dictionaryWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"DCSReflectors" withExtension:@"plist"]];
    
    return _reflectorList;
}

+(void) load {
    [BTRDataEngine registerLinkDriver:self];
}

-(unsigned short)clientPort {
    return 30051;
}
-(unsigned short)serverPort {
    return 30051;
}
-(CFAbsoluteTime)pollInterval {
    return 10.0;
}
-(BOOL)hasReliableChecksum {
    return YES;
}
-(size_t)packetSize {
    return sizeof(struct dcs_packet);
}

-(NSString *)getAddressForReflector:(NSString *)reflector {
    return [NSHost hostWithName:[BTRDCSLink reflectorList][reflector]].address;
}

-(BOOL)canHandleLinkTo:(NSString *)linkTarget {
    if(linkTarget.length != 8)
        return NO;
    
    if([BTRDCSLink reflectorList][linkTarget.callWithoutModule])
        return YES;
    
    return NO;
}
-(NSArray<NSString *> *)destinations {
    return [[BTRDCSLink reflectorList].allKeys copy];
}

-(void)processPacket:(NSData *)packet {
    NSLog(@"Got packet %@", packet);
}
-(void)sendPoll {
    [self doesNotRecognizeSelector:_cmd];
}
-(void)sendLinkPacketWithModule:(char)module {
    if([self.linkTarget isEqualToString:@""])
        return;
    
    NSString *infoHtml = [NSString stringWithFormat:@"<table border='0' width='95%%'><tr><td width='4%%'><img border='0' src='dongle.jpg'><td><td width='96%%'><font size='2'><b>DONGLE %@ %@ (%@)</b></font></td></tr></table>",
                          [[NSBundle mainBundle] infoDictionary][@"CFBundleName"],
                          [[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"],
                          [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"]];
    
    NSLog("HTML is %@", infoHtml);
    NSLog("Structure is %ld bytes", sizeof(struct dcs_packet));
    
    NSMutableData *linkPacket = nil;
    if(module == ' ') {
        linkPacket = [NSMutableData dataWithBytes:&linkTemplate length:19];
    } else {
        linkPacket = [NSMutableData dataWithBytes:&linkTemplate length:519];
        //  XXX Copy the HTML data here.
    }
    
    struct dcs_packet *packet = (struct dcs_packet *)linkPacket.mutableBytes;
    
    //  XXX This works but is ugly.  characterAtIndex returns an unichar, and we should really
    //  XXX do some sort of real UTF8 conversion rather than just casting it down.
    //  XXX Maybe it doesn't make much of a difference since the module should only be
    //  XXX in the range of A-Z.
    NSAssert(self.rpt1Call.length == 8, @"rpt1Call is not 8 characters");
    packet->link.module = (char) [self.rpt1Call characterAtIndex:7];
    packet->link.reflectorModule = module;
    [self.rpt1Call getBytes:packet->link.callsign maxLength:sizeof(packet->link.callsign) usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, 8) remainingRange:NULL];
    [self.linkTarget.paddedCall getBytes:packet->link.request.reflectorCall maxLength:sizeof(packet->link.request.reflectorCall) usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, 7) remainingRange:NULL];
    
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
    [self doesNotRecognizeSelector:_cmd];
}


@end

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
struct dcs_frame {
    char magic[4];
    char flags[3];
    char rpt2Call[8];
    char rpt1Call[8];
    char urCall[8];
    char myCall[8];
    char myCall2[4];
    unsigned short id;
    char sequence;
    char voice[9];
    char data[3];
    char repeaterSequence[3];
    char unknown[3];
    char text[36];
};

struct dcs_poll {
    char callsign[8];
    char null;
    char reflectorCall[8];
};

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
        struct dcs_frame frame;
    };
};

#pragma pack(pop)

static const struct dcs_frame dcsFrameTemplate = {
    .magic = "0001",
    .flags = { 0x00, 0x02, 0x01 },
    .rpt2Call = "        ",
    .rpt1Call = "        ",
    .urCall = "CQCQCQ  ",
    .myCall = "        ",
    .myCall2 = "    ",
    .id = 0,
    .sequence = 0,
    .voice = { 0 },
    .data = { 0 },
    .repeaterSequence = { 0 },
    .unknown = { 0 },
    .text = { 0 }
};

static const struct dcs_packet linkTemplate = {
    .link.callsign = "        ",
    .link.module = 'D',
    .link.reflectorModule = ' ',
    .link.request.terminator = 0x00,
    .link.request.reflectorCall = "        ",
    .link.request.htmlData = { 0x00 }
};

static NSDictionary *_reflectorList;

@interface BTRDCSLink ()

@property int repeaterSequence;

+(NSDictionary *)reflectorList;

-(void)processFrame:(struct dcs_frame *)frame;

@end


@implementation BTRDCSLink

+(NSDictionary *) reflectorList {
    return _reflectorList;
}

+(void) load {
    [BTRDataEngine registerLinkDriver:self];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableDictionary *tmpReflectorList = [NSMutableDictionary dictionaryWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"DCSReflectors" withExtension:@"plist"]];
        [tmpReflectorList addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:@"https://ar-dns.net/dcs.plist"]]];
        _reflectorList = [NSDictionary dictionaryWithDictionary:tmpReflectorList];
    });
}

-(unsigned short)clientPort {
    return 0;
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

-(void)processPacket:(NSData *)packetData {
    struct dcs_packet *packet = (struct dcs_packet *) packetData.bytes;
    
    if(!memcmp(packet, "0001", 4)) {
        [self processFrame:&packet->frame];
        return;
    }
    
    if(!memcmp(packet, "EEEE", 4)) {
        NSLog(@"Got status packet");
        return;
    }
    
    switch(packetData.length) {
        case 17:
        case 22:
            //  Poll packet.  Ignore because this is handled in the superclass.
            break;
        case 14:
        case 19:
        case 519:
            // Link acknowledgment packet
            if(!strncmp(packet->link.response.response, "ACK", 3)) {
                self.linkState = LINKED;
                NSLog(@"Got ACK, going linked");
            } else if(!strncmp(packet->link.response.response, "NAK", 3)) {
                NSLog(@"Got NAK, unlinking");
                NSError *error = [NSError errorWithDomain:@"BTRErrorDomain" code:3 userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ refused the link request", self.linkTarget]}];
                [self.delegate destinationDidError:self.linkTarget error:error];
                [self unlink];
            } else
                NSLog(@"Unknown link acknowledgment");
            break;
        case 35:
            //  Status data
            break;
        default:
            NSLog(@"Unknown link packet size %ld, %@, \"%@\"", packetData.length, packetData, [[NSString alloc] initWithData:packetData encoding:NSASCIIStringEncoding]);
            break;
    }
}

-(void)processFrame:(struct dcs_frame *)frame {
    BTRLinkDriver __weak *weakSelf = self;
    
    //  Ignore packets not in our current stream
    if(self.rxStreamId && self.rxStreamId != frame->id)
        return;
    
    if(!self.rxStreamId) {
        //  XXX There can be null values here!
        NSDictionary *header = @{
                                 @"rpt1Call" : [NSString stringWithCallsign:frame->rpt1Call],
                                 @"rpt2Call" : [NSString stringWithCallsign:frame->rpt2Call],
                                 @"myCall" : [NSString stringWithCallsign:frame->myCall],
                                 @"myCall2" : [NSString stringWithShortCallsign:frame->myCall2],
                                 @"urCall" : [NSString stringWithCallsign:frame->urCall],
                                 @"streamId" : [NSNumber numberWithUnsignedInteger:frame->id],
                                 @"time" : [NSDate date],
                                 @"message" : @""
                                 };
        
        NSLog(@"New stream %@", header);
        self.rxStreamId = frame->id;
        [self.delegate streamDidStart:header];
        self.qsoTimer = [[BTRNetworkTimer alloc] initWithTimeout:5.0 failureHandler: ^{
            [weakSelf terminateCurrentStream];
        }];
    }
 
    [self.qsoTimer ping];
    
    //  XXX This should be using a local variable set by the DataEngine.
    [self.delegate addData:(void *)frame->data streamId:self.rxStreamId];
            
    //  If the 0x40 bit of the sequence is set, this is the last packet of the stream.
    if(frame->sequence & 0x40) {
        [self terminateCurrentStream];
        frame->sequence &= ~0x40;
    }
            
    if(frame->sequence != self.rxSequence) {
        //  If the packet is more recent, reset the sequence, if not, wait for my next packet
        if(isSequenceAhead(frame->sequence, self.rxSequence, 21)) {
            NSLog(@"Skipped packet: incoming %u, sequence = %u",frame->sequence, self.rxSequence);
            self.rxSequence = frame->sequence;
        } else {
            NSLog(@"Out of order packet: incoming = %u, sequence = %u\n", frame->sequence, self.rxSequence);
            return;
        }
    }
            
    if(self.rxStreamId == 0)
        self.rxSequence = 0;
    else
        self.rxSequence = (self.rxSequence + 1) % 21;
            
    //  If streamId == 0, we are on the last packet of this stream.
    [self.vocoder decodeData:frame->voice lastPacket:(self.rxStreamId == 0)];
}


-(void)sendPoll {
    NSMutableData *pollPacket = [NSMutableData dataWithLength:sizeof(struct dcs_poll)];
    struct dcs_poll *poll = pollPacket.mutableBytes;
    
    [self.rpt1Call getBytes:poll->callsign maxLength:sizeof(poll->callsign) usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, sizeof(poll->callsign)) remainingRange:NULL];
    [self.linkTarget getBytes:poll->reflectorCall maxLength:sizeof(poll->reflectorCall) usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, sizeof(poll->reflectorCall)) remainingRange:NULL];
    poll->null = 0x00;
    
    NSLog(@"Sending poll %@", pollPacket);
    
    [self sendPacket:pollPacket];
}


-(void)fillLinkPacket:(struct dcs_packet *)packet {
    //  XXX This works but is ugly.  characterAtIndex returns an unichar, and we should really
    //  XXX do some sort of real UTF8 conversion rather than just casting it down.
    //  XXX Maybe it doesn't make much of a difference since the module should only be
    //  XXX in the range of A-Z.
    NSAssert(self.rpt1Call.length == 8, @"rpt1Call is not 8 characters");
    packet->link.module = (char) [self.rpt1Call characterAtIndex:7];
    [self.rpt1Call getBytes:packet->link.callsign maxLength:sizeof(packet->link.callsign) usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, 8) remainingRange:NULL];
    [self.linkTarget.paddedCall getBytes:packet->link.request.reflectorCall maxLength:sizeof(packet->link.request.reflectorCall) usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, 7) remainingRange:NULL];
}

-(void)sendUnlink {
    if([self.linkTarget isEqualToString:@""])
        return;

    NSMutableData *linkPacket = [NSMutableData dataWithBytes:&linkTemplate length:19];  //  XXX Can we get rid of the magic size?
    struct dcs_packet *packet = (struct dcs_packet *)linkPacket.mutableBytes;

    [self fillLinkPacket:packet];
    packet->link.reflectorModule = ' ';
    [self sendPacket:linkPacket];

    self.linkState = UNLINKED;
}

-(void)sendLink {
    NSLog(@"Sending link packet");
    
    if([self.linkTarget isEqualToString:@""])
        return;
    
    NSString *infoHtml = [NSString stringWithFormat:@"<table border='0' width='95%%'><tr><td width='4%%'><img border='0' src='dongle.jpg'><td><td width='96%%'><font size='2'><b>DONGLE %@ %@ (%@)</b></font></td></tr></table>",
                          [[NSBundle mainBundle] infoDictionary][@"CFBundleName"],
                          [[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"],
                          [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"]];
    
    NSMutableData *linkPacket = [NSMutableData dataWithBytes:&linkTemplate length:519];  //  XXX Can we get rid of the magic size?
    struct dcs_packet *packet = (struct dcs_packet *)linkPacket.mutableBytes;
    
    [self fillLinkPacket:packet];
    packet->link.reflectorModule = (char) [self.linkTarget.paddedCall characterAtIndex:7];
    [infoHtml getBytes:packet->link.request.htmlData maxLength:sizeof(packet->link.request.htmlData) usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, 500) remainingRange:NULL];

    [self sendPacket:linkPacket];
}

-(void) sendAMBE:(void *)data lastPacket:(BOOL)last {
    if(self.linkState != LINKED)
        return;
    
    BTRLinkDriver __weak *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSMutableData *frameData = [NSMutableData dataWithBytes:&dcsFrameTemplate length:sizeof(dcsFrameTemplate)];
        struct dcs_frame *frame = frameData.mutableBytes;

       frame->id = weakSelf.txStreamId;
        
        [weakSelf.myCall.paddedCall getBytes:frame->myCall maxLength:8 usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, 8) remainingRange:NULL];
        [weakSelf.myCall2.paddedShortCall getBytes:frame->myCall2 maxLength:4 usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, 4) remainingRange:NULL];
        [weakSelf.rpt1Call.paddedCall getBytes:frame->rpt1Call maxLength:8 usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, 8) remainingRange:NULL];
        [weakSelf.linkTarget.paddedCall getBytes:frame->rpt2Call maxLength:8 usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, 8) remainingRange:NULL];
        if(self.txSequence == 0) {  //  XXX This doesn't detect correctly whether it is indeed the first packet.
            NSDictionary *streamInfo = @{
                                         @"rpt1Call" : weakSelf.rpt1Call,
                                         @"rpt2Call" : weakSelf.linkTarget,
                                         @"myCall" : weakSelf.myCall,
                                         @"myCall2" : weakSelf.myCall2,
                                         @"urCall" : @"CQCQCQ",
                                         @"streamId" : [NSNumber numberWithUnsignedShort:weakSelf.txStreamId],
                                         @"time" : [NSDate date],
                                         @"direction" : @"TX",
                                         @"message" : @""
                                         };
            [weakSelf.delegate streamDidStart:streamInfo];
        }
        
        frame->sequence = weakSelf.txSequence;

        [self.delegate getBytes:&frame->data forSequence:weakSelf.txSequence];
        
        if(last) {
            [self.delegate streamDidEnd:[NSNumber numberWithUnsignedShort:weakSelf.txStreamId] atTime:[NSDate date]];
            weakSelf.txSequence = 0;
            weakSelf.txStreamId = (short) random();
            frame->sequence |= 0x40;
        } else {
            memcpy(&frame->voice, data, sizeof(frame->voice));
            weakSelf.txSequence = (weakSelf.txSequence + 1) % 21;
        }
        
        //  Deal with the repeater sequence
        ++self.repeaterSequence;
        if(self.repeaterSequence > 0x0FFF)
            self.repeaterSequence = 0;
        
        frame->repeaterSequence[2] = (self.repeaterSequence >> 16) & 0xFF;
        frame->repeaterSequence[1] = (self.repeaterSequence >> 8) & 0xFF;
        frame->repeaterSequence[0] = (self.repeaterSequence) & 0xFF;
        
        [weakSelf sendPacket:frameData];
    });
}


@end

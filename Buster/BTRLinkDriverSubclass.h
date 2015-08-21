//
//  BTRLinkDriverSubclass.h
//  Buster
//
//  Created by Jeremy McDermond on 8/18/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "BTRLinkDriver.h"

#define call_to_nsstring(a) [[NSString alloc] initWithBytes:(a) length:sizeof((a)) encoding:NSUTF8StringEncoding]

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


#pragma pack(push, 1)
struct dstar_ambe_data {
    char voice[9];
    char data[3];
    char endPattern[6];
};
struct dstar_header_data{
    char flags[3];
    char rpt2Call[8];
    char rpt1Call[8];
    char urCall[8];
    char myCall[8];
    char myCall2[4];
    unsigned short sum;
};
struct dstar_frame {
    char magic[4];  //  "DSVT"
    char type;  //  0x20 = AMBE, 0x10 = Header
    char unknown[4]; // { 0x00, 0x00, 0x00, 0x20 }
    char band[3]; //  { 0x00, 0x02, 0x01 }
    unsigned short id;
    char sequence;
    union {
        struct dstar_ambe_data ambe;
        struct dstar_header_data header;
    };
};
#pragma pack(pop)

NS_INLINE size_t dstar_frame_size(struct dstar_frame *frame) {
    switch(frame->type) {
        case 0x10:
            return 15 + sizeof(struct dstar_header_data);
        case 0x20:
            return 15 + sizeof(struct dstar_ambe_data) - sizeof(((struct dstar_ambe_data *)0)->endPattern);
        default:
            return 0;
    }
}

#define AMBE_NULL_PATTERN { 0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8 }

static const struct dstar_frame dstar_header_template = {
    .magic = "DSVT",
    .type = 0x10,
    .unknown = { 0x00, 0x00, 0x00, 0x20 },
    .band = { 0x00, 0x02, 0x01 },
    .id = 0,
    .sequence = 0x80,
    .header.flags = { 0x00, 0x00, 0x00 },
    .header.myCall = "        ",
    .header.urCall = "CQCQCQ  ",
    .header.rpt1Call = "        ",
    .header.rpt2Call = "        ",
    .header.myCall2 = "    ",
    .header.sum = 0xFFFF
};

static const struct dstar_frame dstar_ambe_template = {
    .magic = "DSVT",
    .type = 0x20,
    .unknown = { 0x00, 0x00, 0x00, 0x20 },
    .band = { 0x00, 0x02, 0x01 },
    .id = 0,
    .sequence = 0,
    .ambe.voice = { 0 },
    .ambe.data = { 0 },
    .ambe.endPattern = { 0 }
};


@interface BTRLinkDriver ()

//
//  Methods for the subclass to override
//
-(void)processPacket:(NSData *)packet;
-(NSString *)getAddressForReflector:(NSString *)reflector;
-(void)sendPoll;
-(void)sendUnlink;
-(void)sendLink;
-(void)sendFrame:(struct dstar_frame *)frame;

//
//  Pass off the D-STAR frame data to the rest of the system.
//  This needs to be called when we receive a D-STAR frame from the reflector.
//
-(void)processFrame:(struct dstar_frame *)frame;

//
//  Send a packet to the reflector.  This is an NSData so we know the length of the packet.
//
-(void)sendPacket:(NSData *)packet;

// -(void)unlink;

//
//  Override these to set the parameters in the subclass.
//
@property (nonatomic, readonly) CFAbsoluteTime pollInterval;
@property (nonatomic, readonly) unsigned short clientPort;
@property (nonatomic, readonly) unsigned short serverPort;
@property (nonatomic, readonly) size_t packetSize;

//
//  Properties subclasses might need.  You should take care of making sure linkState is correct.
//
@property (nonatomic, readwrite) enum linkState linkState;
@end

//
//  Utilities to create callsign strings to fill packets.
//
@interface NSString (BTRCallsignUtils)
@property (nonatomic, readonly) NSString *paddedCall;
@property (nonatomic, readonly) NSString *callWithoutModule;
@property (nonatomic, readonly) NSString *paddedShortCall;

+(NSString *)stringWithCallsign:(void *)callsign;
+(NSString *)stringWithShortCallsign:(void *)callsign;

@end
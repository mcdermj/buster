//
//  BTRDV3KVocoder.m
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

#import "BTRDV3KVocoder.h"
#import "BTRDV3KVocoderSubclass.h"

#import "BTRDataEngine.h"
#import "BTRDV3KPacket.h"
#import "BTRGatewayHandler.h"
#import "BTRAudioHandler.h"

static const struct dv3k_packet bleepPacket = {
    .start_byte = DV3K_START_BYTE,
    .header.packet_type = DV3K_TYPE_AMBE,
    .header.payload_length = htons(sizeof(bleepPacket.payload.ambe)),
    .payload.ambe.data.field_id = DV3K_AMBE_FIELD_CHAND,
    .payload.ambe.data.num_bits = sizeof(bleepPacket.payload.ambe.data.data) * 8,
    .payload.ambe.data.data = {0},
    .payload.ambe.cmode.field_id = DV3K_AMBE_FIELD_CMODE,
    .payload.ambe.cmode.value = htons(0x4000),
    .payload.ambe.tone.field_id = DV3K_AMBE_FIELD_TONE,
    .payload.ambe.tone.tone = 0x40,
    .payload.ambe.tone.amplitude = 0x00
};

static const struct dv3k_packet silencePacket = {
    .start_byte = DV3K_START_BYTE,
    .header.packet_type = DV3K_TYPE_AMBE,
    .header.payload_length = htons(sizeof(silencePacket.payload.ambe.data) + sizeof(silencePacket.payload.ambe.cmode)),
    .payload.ambe.data.field_id = DV3K_AMBE_FIELD_CHAND,
    .payload.ambe.data.num_bits = sizeof(silencePacket.payload.ambe.data.data) * 8,
    .payload.ambe.data.data = {0},
    .payload.ambe.cmode.field_id = DV3K_AMBE_FIELD_CMODE,
    .payload.ambe.cmode.value = 0x0000
};

static const struct dv3k_packet dv3k_audio = {
    .start_byte = DV3K_START_BYTE,
    .header.packet_type = DV3K_TYPE_AUDIO,
    .header.payload_length = htons(sizeof(dv3k_audio.payload.audio)),
    .payload.audio.field_id = DV3K_AUDIO_FIELD_SPEECHD,
    .payload.audio.num_samples = sizeof(dv3k_audio.payload.audio.samples) / sizeof(short),
    .payload.audio.cmode_field_id = 0x02,
    .payload.audio.cmode_value = htons(0x4000)
};

#pragma mark - Private interface

@interface BTRDV3KVocoder () {
    dispatch_queue_t dispatchQueue;
    // dispatch_queue_t readDispatchQueue;
    dispatch_source_t dispatchSource;
    struct dv3k_packet dv3k_ambe;
    struct dv3k_packet *responsePacket;
}

@property (nonatomic, readwrite, copy) NSString *productId;
@property (nonatomic, readwrite, copy) NSString *version;

- (BOOL) sendCtrlPacket:(struct dv3k_packet)packet expectResponse:(uint8)response;
- (void) processPacket;
@end

@implementation BTRDV3KVocoder

@synthesize audio;

#pragma mark - Lifecycle

- (id) init {
    self = [super init];
    
    if(self) {
        dv3k_ambe.start_byte = DV3K_START_BYTE;
        dv3k_ambe.header.packet_type = DV3K_TYPE_AMBE;
        dv3k_ambe.header.payload_length = htons(sizeof(dv3k_ambe.payload.ambe.data));
        dv3k_ambe.payload.ambe.data.field_id = DV3K_AMBE_FIELD_CHAND;
        dv3k_ambe.payload.ambe.data.num_bits = sizeof(dv3k_ambe.payload.ambe.data.data) * 8;
        
        dispatch_queue_attr_t dispatchQueueAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
        dispatchQueue = dispatch_queue_create("net.nh6z.Dummy.SerialIO.Write", dispatchQueueAttr);
        // readDispatchQueue = dispatch_queue_create("net.nh6z.Dummy.SerialIO.Read", dispatchQueueAttr);
        dispatchSource = NULL;
        
        responsePacket = calloc(1, sizeof(struct dv3k_packet));
                
        self.beep = YES;
        
        self.started = NO;
    }
    
    return self;
}

- (void) dealloc {
    free(responsePacket);
}

#pragma mark - Methods for subclasses to implement
- (BOOL) openPort {
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (BOOL) setNonblocking {
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (BOOL) readPacket:(struct dv3k_packet *)packet {
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (BOOL) writePacket:(const struct dv3k_packet *)packet {
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

-(void) closePort {
    [self doesNotRecognizeSelector:_cmd];
}

#pragma mark - Packet sending

- (BOOL) sendCtrlPacket:(struct dv3k_packet)packet expectResponse:(uint8)response {
    
    if(self.started == YES) {
        NSLog(@"Called sendCtrlPacket: when started\n");
        return NO;
    }
    
    if(![self writePacket:&packet])
        return NO;
    
    if(![self readPacket:responsePacket])
        return NO;
    
    if(responsePacket->start_byte != DV3K_START_BYTE ||
       responsePacket->header.packet_type != DV3K_TYPE_CONTROL ||
       responsePacket->payload.ctrl.field_id != response) {
        NSLog(@"Couldn't get control response\n");
        return NO;
    }
    
    return YES;
}

#pragma mark - Flow Control

- (BOOL) start {
    if(self.started == YES) {
        NSLog(@"DV3K is not closed\n");
        return YES;
    }
    
    self.version = @"";
    self.productId = @"";
    
    [self openPort];
    
    //  Initialize the DV3K
    struct dv3k_packet ctrlPacket = {
        .start_byte = DV3K_START_BYTE,
        .header.packet_type = DV3K_TYPE_CONTROL,
        .header.payload_length = htons(1),
        .payload.ctrl.field_id = DV3K_CONTROL_RESET
    };
    if(![self sendCtrlPacket:ctrlPacket expectResponse:DV3K_CONTROL_READY]) {
        NSLog(@"Couldn't Reset DV3000: %s\n", strerror(errno));
        [self closePort];
        return NO;
    }
    
    ctrlPacket.payload.ctrl.field_id = DV3K_CONTROL_PRODID;
    if(![self sendCtrlPacket:ctrlPacket expectResponse:DV3K_CONTROL_PRODID]) {
        NSLog(@"Couldn't query product id: %s\n", strerror(errno));
        [self closePort];
        return NO;
    }
    NSString *tmpProductId = [NSString stringWithCString:responsePacket->payload.ctrl.data.prodid encoding:NSUTF8StringEncoding];
    
    ctrlPacket.payload.ctrl.field_id = DV3K_CONTROL_VERSTRING;
    if(![self sendCtrlPacket:ctrlPacket expectResponse:DV3K_CONTROL_VERSTRING]) {
        NSLog(@"Couldn't query version: %s\n", strerror(errno));
        [self closePort];
        return NO;
        
    }
    NSString *tmpVersion = [NSString stringWithCString:responsePacket->payload.ctrl.data.version encoding:NSUTF8StringEncoding];
    
    
    //  Set up the Vocoder
    ctrlPacket.header.payload_length = htons(sizeof(ctrlPacket.payload.ctrl.data.ratep) + 1);
    ctrlPacket.payload.ctrl.field_id = DV3K_CONTROL_RATEP;
    memcpy(ctrlPacket.payload.ctrl.data.ratep, ratep_values, sizeof(ratep_values));
    if([self sendCtrlPacket:ctrlPacket expectResponse:DV3K_CONTROL_RATEP] == NO) {
        NSLog(@"Couldn't send RATEP request: %s\n", strerror(errno));
        [self closePort];
        return NO;
    }
    
    ctrlPacket.header.payload_length = htons(sizeof(ctrlPacket.payload.ctrl.data.chanfmt) + 1);
    ctrlPacket.payload.ctrl.field_id = DV3K_CONTROL_CHANFMT;
    ctrlPacket.payload.ctrl.data.chanfmt = htons(0x0001);
    if([self sendCtrlPacket:ctrlPacket expectResponse:DV3K_CONTROL_CHANFMT] == NO) {
        NSLog(@"Couldn't send CHANFMT request: %s\n", strerror(errno));
        [self closePort];
        return NO;
    }
    
    NSLog(@"DV3000 is now set up\n");
    
    [self setNonblocking];

    dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) self.descriptor, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    
    //dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) self.descriptor, 0, readDispatchQueue);
    BTRDV3KVocoder __weak *weakSelf = self;
    dispatch_source_set_event_handler(dispatchSource, ^{
        [weakSelf processPacket];
    });
    
    dispatch_source_set_cancel_handler(dispatchSource, ^{
        [self closePort];
    });
    
    dispatch_resume(dispatchSource);
    
    NSLog(@"Completed serial setup\n");
    
    self.productId = tmpProductId;
    self.version = tmpVersion;
    
    NSLog(@"Product ID is %@\n", self.productId);
    NSLog(@"Version is %@\n", self.version);
    
    self.started = YES;
    
    return YES;
}

- (void) stop {
    if(self.started == NO) {
        NSLog(@"DV3K isn't started\n");
        return;
    }
    
    dispatch_source_cancel(dispatchSource);
    
    self.productId = @"";
    self.version = @"";
    
    self.started = NO;
}

#pragma mark - Data handling

- (void) decodeData:(void *) data lastPacket:(BOOL)last {
    struct dv3k_packet *packet;
    
    if(self.started == NO)
        return;
    
    packet = malloc(sizeof(struct dv3k_packet));
    
    memcpy(packet, &dv3k_ambe, sizeof(dv3k_ambe));
    memcpy(&packet->payload.ambe.data.data, data, sizeof(packet->payload.ambe.data.data));
    
    dispatch_async(dispatchQueue, ^{
        [self writePacket:packet];
        
        if(last && self.beep) {
            for(int i = 0; i < 5; ++i)
                [self writePacket:&bleepPacket];
            
            //  Write a silence packet to clean out the chain
            [self writePacket:&silencePacket];
        }
        
        free(packet);
    });
}

- (void) encodeData:(void *)  data lastPacket:(BOOL)last {
    struct dv3k_packet *packet;
    
    if(self.started == NO)
        return;
    
    packet = malloc(sizeof(struct dv3k_packet));
    memcpy(packet, &dv3k_audio, sizeof(struct dv3k_packet));
    memcpy(&packet->payload.audio.samples, data, sizeof(packet->payload.audio.samples));
    
    if(last)
        packet->payload.audio.cmode_value = htons(0x4000);
    else
        packet->payload.audio.cmode_value = 0x0000;
    
    dispatch_async(dispatchQueue, ^{
        [self writePacket:packet];
        
        free(packet);
    });
}

-(void) processPacket {
    BOOL last = NO;
    
    if(![self readPacket:responsePacket])
        return;
    
    switch(responsePacket->header.packet_type) {
        case DV3K_TYPE_CONTROL:
            NSLog(@"DV3K Control Packet Received\n");
            break;
        case DV3K_TYPE_AMBE:
            if(responsePacket->payload.ambe.data.field_id != DV3K_AMBE_FIELD_CHAND ||
               responsePacket->payload.ambe.data.num_bits != sizeof(responsePacket->payload.ambe.data.data) * 8) {
                NSLog(@"Received invalid AMBE packet", ntohs(responsePacket->header.payload_length));
                return;
            }
            
            if(responsePacket->payload.ambe.cmode.field_id == DV3K_AMBE_FIELD_CMODE &&
               (htons(responsePacket->payload.ambe.cmode.value) & 0x8000)) {
                last = YES;
                NSLog(@"Last Packet");
            }
            
            [[BTRDataEngine sharedInstance].network sendAMBE:responsePacket->payload.ambe.data.data lastPacket:last];
            
            break;
        case DV3K_TYPE_AUDIO:
            if(responsePacket->payload.audio.field_id != DV3K_AUDIO_FIELD_SPEECHD ||
               responsePacket->payload.audio.num_samples != sizeof(responsePacket->payload.audio.samples) / sizeof(short)) {
                NSLog(@"Received invalid audio packet\n");
                return;
            }
            [self.audio queueAudioData:&responsePacket->payload.audio.samples withLength:sizeof(responsePacket->payload.audio.samples)];
            break;
    }
}

@end

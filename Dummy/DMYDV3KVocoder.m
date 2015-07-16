//
//  DMYDV3KVocoder.m
//  Dummy
//
//  Created by Jeremy McDermond on 7/12/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import "DMYDV3KVocoder.h"

#import <termios.h>
#import <sys/ioctl.h>
#import <IOKit/serial/ioss.h>

// #define NSLog(x...)

#define DV3000_TYPE_CONTROL 0x00
#define DV3000_TYPE_AMBE 0x01
#define DV3000_TYPE_AUDIO 0x02

static const unsigned char DV3000_START_BYTE   = 0x61;

static const unsigned char DV3000_CONTROL_RATEP  = 0x0A;
static const unsigned char DV3000_CONTROL_PRODID = 0x30;
static const unsigned char DV3000_CONTROL_VERSTRING = 0x31;
static const unsigned char DV3000_CONTROL_RESET = 0x33;
static const unsigned char DV3000_CONTROL_READY = 0x39;

static const char ratep_values[12] = { 0x01, 0x30, 0x07, 0x63, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x48 };

#pragma pack(push, 1)
struct dv3k_packet {
    unsigned char start_byte;
    struct {
        unsigned short payload_length;
        unsigned char packet_type;
    } header;
    union {
        struct {
            unsigned char field_id;
            union {
                char prodid[16];
                char ratep[12];
                char version[48];
            } data;
        } ctrl;
        struct {
            unsigned char field_id;
            unsigned char num_samples;
            short samples[160];
        } audio;
        struct {
            unsigned char field_id;
            unsigned char num_bits;
            unsigned char data[9];
        } ambe;
    } payload;
};
#pragma pack(pop)

@interface DMYDV3KVocoder () {
    int serialDescriptor;
    dispatch_queue_t dispatchQueue;
    dispatch_source_t dispatchSource;
    struct dv3k_packet dv3k_ambe;
    struct dv3k_packet *responsePacket;
}

- (BOOL) readPacket:(struct dv3k_packet *)packet;
- (BOOL) sendCtrlPacket:(struct dv3k_packet)packet expectResponse:(uint8)response;
- (void) processPacket;
@end

@implementation DMYDV3KVocoder

@synthesize serialPort;
@synthesize productId;
@synthesize version;
@synthesize speed;
@synthesize audio;

- (id) initWithPort:(NSString *)_serialPort {
    self = [super init];
    
    if(self) {
        serialPort = _serialPort;

        dv3k_ambe.start_byte = DV3000_START_BYTE;
        dv3k_ambe.header.packet_type = DV3000_TYPE_AMBE;
        dv3k_ambe.header.payload_length = htons(sizeof(dv3k_ambe.payload.ambe));
        dv3k_ambe.payload.ambe.field_id = 0x01;
        dv3k_ambe.payload.ambe.num_bits = sizeof(dv3k_ambe.payload.ambe.data) * 8;
        
        dispatch_queue_attr_t dispatchQueueAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
        dispatchQueue = dispatch_queue_create("net.nh6z.Dummy.SerialIO", dispatchQueueAttr);
        dispatchSource = NULL;
        
        responsePacket = calloc(1, sizeof(struct dv3k_packet));
        
        speed = 230400;
    }
    
    return self;
}

- (BOOL) readPacket:(struct dv3k_packet *)packet {
    ssize_t bytes;
    size_t bytesLeft;
    
    packet->start_byte = 0x00;
    
    bytes = read(serialDescriptor, packet, 1);
    if(bytes == -1 && errno != EAGAIN)
        NSLog(@"Couldn't read start byte: %s\n", strerror(errno));
    if(packet->start_byte != DV3000_START_BYTE)
        return NO;
    
    bytesLeft = sizeof(packet->header);
    while(bytesLeft > 0) {
        bytes = read(serialDescriptor, ((uint8_t *) &packet->header) + sizeof(packet->header) - bytesLeft, bytesLeft);
        if(bytes == -1) {
            if(errno == EAGAIN) continue;
            NSLog(@"Couldn't read header: %s\n", strerror(errno));
            return NO;
        }
        
        bytesLeft -= (size_t) bytes;
    }
    
    bytesLeft = ntohs(packet->header.payload_length);
    if(bytesLeft > sizeof(packet->payload)) {
        NSLog(@"Payload exceeds buffer size: %ld\n", bytesLeft);
        return NO;
    }
    
    while(bytesLeft > 0) {
        bytes = read(serialDescriptor, ((uint8_t *) &packet->payload) + (ntohs(packet->header.payload_length) - bytesLeft), bytesLeft);
         if(bytes == -1) {
            if(errno == EAGAIN) continue;
            NSLog(@"Couldn't read payload: %s\n", strerror(errno));
            return NO;
        }
        
        bytesLeft -= (size_t) bytes;
    }

    return YES;
}

- (BOOL) sendCtrlPacket:(struct dv3k_packet)packet expectResponse:(uint8)response {
    
    if(dispatchSource != NULL) {
        NSLog(@"Called sendCtrlPacket: when started\n");
        return NO;
    }
    
    if(write(serialDescriptor, &packet, sizeof(packet.header) + ntohs(packet.header.payload_length) + 1) == -1) {
        NSLog(@"Couldn't write control packet\n");
        return NO;
    }
    
    if([self readPacket:responsePacket] == NO)
        return NO;
    
    if(responsePacket->start_byte != DV3000_START_BYTE ||
       responsePacket->header.packet_type != DV3000_TYPE_CONTROL ||
       responsePacket->payload.ctrl.field_id != response) {
        NSLog(@"Couldn't get control response\n");
        return NO;
    }

    return YES;
}

- (BOOL) start {
    struct termios portTermios;
    
    serialDescriptor = open([serialPort cStringUsingEncoding:NSUTF8StringEncoding], O_RDWR | O_NOCTTY);
    if(serialDescriptor == -1) {
        NSLog(@"Error opening DV3000 Serial Port: %s\n", strerror(errno));
        return NO;
    }
    
    if(tcgetattr(serialDescriptor, &portTermios) == -1) {
        NSLog(@"Cannot get terminal attributes: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    portTermios.c_lflag    &= ~(ECHO | ECHOE | ICANON | IEXTEN | ISIG);
    portTermios.c_iflag    &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON | IXOFF | IXANY);
    portTermios.c_cflag    &= ~(CSIZE | CSTOPB | PARENB | CRTSCTS);
    portTermios.c_cflag    |= CS8;
    portTermios.c_oflag    &= ~(OPOST);
    //portTermios.c_cc[VMIN]  = 1 + sizeof(responsePacket->header) + sizeof(responsePacket->payload.ambe);
    portTermios.c_cc[VMIN] = 0;
    portTermios.c_cc[VTIME] = 5;
    
    if(tcsetattr(serialDescriptor, TCSANOW, &portTermios) == -1) {
        NSLog(@"Cannot set terminal attributes: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    if(ioctl(serialDescriptor, IOSSIOSPEED, &speed) == -1) {
        NSLog(@"Cannot set terminal baud rate: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    //  Initialize the DV3K
    struct dv3k_packet ctrlPacket = {
        .start_byte = DV3000_START_BYTE,
        .header.packet_type = DV3000_TYPE_CONTROL,
        .header.payload_length = htons(1),
        .payload.ctrl.field_id = DV3000_CONTROL_RESET
    };
    if([self sendCtrlPacket:ctrlPacket expectResponse:DV3000_CONTROL_READY] == NO) {
        NSLog(@"Couldn't Reset DV3000: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    ctrlPacket.payload.ctrl.field_id = DV3000_CONTROL_PRODID;
    if([self sendCtrlPacket:ctrlPacket expectResponse:DV3000_CONTROL_PRODID] == NO) {
        NSLog(@"Couldn't query product id: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    self.productId = [NSString stringWithCString:responsePacket->payload.ctrl.data.prodid encoding:NSUTF8StringEncoding];
    
    ctrlPacket.payload.ctrl.field_id = DV3000_CONTROL_VERSTRING;
    if([self sendCtrlPacket:ctrlPacket expectResponse:DV3000_CONTROL_VERSTRING] == NO) {
        NSLog(@"Couldn't query version: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
        
    }
    self.version = [NSString stringWithCString:responsePacket->payload.ctrl.data.version encoding:NSUTF8StringEncoding];
   
    NSLog(@"Product ID is %@\n", self.productId);
    NSLog(@"Version is %@\n", self.version);
    
    //  Set up the Vocoder
    ctrlPacket.header.payload_length = htons(sizeof(ctrlPacket.payload.ctrl.data.ratep) + 1);
    ctrlPacket.payload.ctrl.field_id = DV3000_CONTROL_RATEP;
    memcpy(ctrlPacket.payload.ctrl.data.ratep, ratep_values, sizeof(ratep_values));
    if([self sendCtrlPacket:ctrlPacket expectResponse:DV3000_CONTROL_RATEP] == NO) {
        NSLog(@"Couldn't send RATEP request: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    NSLog(@"DV3000 is now set up\n");
    
    if(fcntl(serialDescriptor, F_SETFL, O_NONBLOCK | O_NDELAY) == -1) {
        NSLog(@"Couldn't set O_NONBLOCK: %s\n", strerror(errno));
    }
    
    dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) serialDescriptor, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    DMYDV3KVocoder __weak *weakSelf = self;
    dispatch_source_set_event_handler(dispatchSource, ^{
        [weakSelf processPacket];
    });
    
    dispatch_source_set_cancel_handler(dispatchSource, ^{ close(serialDescriptor); });
    
    dispatch_resume(dispatchSource);
    
    NSLog(@"Completed serial setup\n");
    
    return YES;
}

- (void) dealloc {
    free(responsePacket);
}

- (void) decodeData:(void *) data {
    dispatch_async(dispatchQueue, ^{
        ssize_t bytes;
        
        memcpy(&dv3k_ambe.payload.ambe.data, data, sizeof(dv3k_ambe.payload.ambe.data));
        
        bytes = write(serialDescriptor, &dv3k_ambe, sizeof(dv3k_ambe.header) + ntohs(dv3k_ambe.header.payload_length) + 1);
        if(bytes == -1) {
            NSLog(@"Couldn't send AMBE packet: %s\n", strerror(errno));
            return;
        }
    });    
}

-(void) processPacket {
    if([self readPacket:responsePacket] == NO)
        return;
    
    switch(responsePacket->header.packet_type) {
        case DV3000_TYPE_CONTROL:
            NSLog(@"DV3K Control Packet Received\n");
            break;
        case DV3000_TYPE_AMBE:
            NSLog(@"DV3K AMBE Packet Received\n");
            break;
        case DV3000_TYPE_AUDIO:
            if(responsePacket->payload.audio.field_id != 0x00 ||
               responsePacket->payload.audio.num_samples != sizeof(responsePacket->payload.audio.samples) / sizeof(short)) {
                NSLog(@"Received invalid audio packet\n");
                return;
            }
            [audio queueAudioData:&responsePacket->payload.audio.samples withLength:sizeof(responsePacket->payload.audio.samples)];
            // NSLog(@"DV3K Audio Packet Received\n");
            break;
    }
}

@end

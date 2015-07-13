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

const unsigned char DV3000_START_BYTE   = 0x61;

const unsigned char DV3000_TYPE_CONTROL = 0x00;
const unsigned char DV3000_TYPE_AMBE    = 0x01;
const unsigned char DV3000_TYPE_AUDIO   = 0x02;

const unsigned char DV3000_CONTROL_RATEP  = 0x0A;
const unsigned char DV3000_CONTROL_PRODID = 0x30;
const unsigned char DV3000_CONTROL_VERSTRING = 0x31;
const unsigned char DV3000_CONTROL_RESET = 0x33;
const unsigned char DV3000_CONTROL_READY = 0x39;

#pragma pack(push, 1)
struct dv3k_packet {
    unsigned char start_byte;
    struct {
        unsigned short payload_length;
        unsigned char packet_type;
    } header;
    union {
        unsigned char raw[322];
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

// Can these two be combined, or is it worth it?
const struct dv3k_packet dv3k_prodid = {
    .start_byte = DV3000_START_BYTE,
    .header.packet_type = DV3000_TYPE_CONTROL,
    .header.payload_length = htons(1),
    .payload.ctrl.field_id = DV3000_CONTROL_PRODID
};

const struct dv3k_packet dv3k_vers = {
    .start_byte = DV3000_START_BYTE,
    .header.packet_type = DV3000_TYPE_CONTROL,
    .header.payload_length = htons(1),
    .payload.ctrl.field_id = DV3000_CONTROL_VERSTRING
};

const struct dv3k_packet dv3k_reset = {
    .start_byte = DV3000_START_BYTE,
    .header.packet_type = DV3000_TYPE_CONTROL,
    .header.payload_length = htons(1),
    .payload.ctrl.field_id = DV3000_CONTROL_RESET
};


const struct dv3k_packet dv3k_ratep = {
    .start_byte = DV3000_START_BYTE,
    .header.packet_type = DV3000_TYPE_CONTROL,
    .header.payload_length = htons(sizeof(dv3k_ratep.payload.ctrl.data.ratep) + 1),
    .payload.ctrl.field_id = DV3000_CONTROL_RATEP,
    .payload.ctrl.data.ratep = { 0x01, 0x30, 0x07, 0x63, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x48 }
};

/* const struct dv3k_packet dv3k_ambe = {
    .start_byte = DV3000_START_BYTE,
    .header.packet_type = DV3000_TYPE_AMBE,
    .header.payload_length = htons(sizeof(dv3k_ambe.payload.ambe)),
    .payload.ambe.field_id = 0x01,
    .payload.ambe.num_bits = sizeof(dv3k_ambe.payload.ambe.data) * 8
}; */

const struct dv3k_packet dv3k_audio = {
    .start_byte =  DV3000_START_BYTE,
    .header.packet_type = DV3000_TYPE_AUDIO,
    .header.payload_length = htons(sizeof(dv3k_audio.payload.audio)),
    .payload.audio.field_id = 0x01,
    .payload.audio.num_samples = sizeof(dv3k_audio.payload.audio.samples) / sizeof(short)
};

@interface DMYDV3KVocoder () {
    int serialDescriptor;
    dispatch_source_t dispatchSource;
    dispatch_queue_t dispatchQueue;
    struct dv3k_packet dv3k_ambe;
    NSOperationQueue *ioQueue;
}

- (void) processPacket;
- (BOOL) readPacket:(struct dv3k_packet *)packet;
@end

@implementation DMYDV3KVocoder

@synthesize serialPort;
@synthesize productId;
@synthesize version;

- (id) initWithPort:(NSString *)_serialPort {
    self = [super init];
    
    if(self) {
        self.serialPort = _serialPort;

        dv3k_ambe.start_byte = DV3000_START_BYTE;
        dv3k_ambe.header.packet_type = DV3000_TYPE_AMBE;
        dv3k_ambe.header.payload_length = htons(sizeof(dv3k_ambe.payload.ambe));
        dv3k_ambe.payload.ambe.field_id = 0x01;
        dv3k_ambe.payload.ambe.num_bits = sizeof(dv3k_ambe.payload.ambe.data) * 8;
        
        //ioQueue = [[NSOperationQueue alloc] init];
        //ioQueue.maxConcurrentOperationCount = 1;
        
        dispatch_queue_attr_t dispatchQueueAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
        dispatchQueue = dispatch_queue_create("net.nh6z.Dummy.SerialIO", dispatchQueueAttr);
        
    }
    
    return self;
}

- (BOOL) readPacket:(struct dv3k_packet *)packet {
    ssize_t bytes;
    char input;
    int offset = 0;
    int failedReads = 0;
    
    //memset(packet, 0, sizeof(struct dv3k_packet));
    packet->start_byte = 0x00;
    
    do {
        bytes = read(serialDescriptor, packet, 1);
        if(bytes == -1) {
            NSLog(@"Couldn't byte from descriptor: %s\n", strerror(errno));
        }
        if(bytes == 0)
            return NO;
        
        //if(packet->start_byte != DV3000_START_BYTE)
        //    NSLog(@"got byte 0x%02hhx\n", packet->start_byte);
        
        ++offset;
        
        // NSLog(@"Got byte 0x%02x\n", input);
        
    } while (packet->start_byte != DV3000_START_BYTE);
    
    //if(offset > 1)
    //    NSLog(@"Needed to read %d bytes with %d failed reads before finding sync\n", offset, failedReads);
    
    bytes = read(serialDescriptor, &packet->header, sizeof(packet->header));
    if(bytes == -1) {
        NSLog(@"Couldn't read product id header: %s\n", strerror(errno));
        return NO;
    }
    
    if(bytes == 0) {
        NSLog(@"No bytes read from socket\n");
        return NO;
    }
    
    /* if(packet->start_byte != DV3000_START_BYTE) {
        NSLog(@"Received invalid DV3K packet\n");
        [self findStartByte];
        return NO;
    } */
    
    bytes = read(serialDescriptor, &packet->payload, ntohs(packet->header.payload_length));
    if(bytes == -1) {
        NSLog(@"Couldn't read product id payload: %s\n", strerror(errno));
        return NO;
    }
    
    return YES;
}

- (BOOL) start {
    
    struct dv3k_packet responsePacket;
    ssize_t bytes = 0;
    struct termios portTermios;
    int i = 0;
    
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
    portTermios.c_cc[VMIN]  = 0;
    portTermios.c_cc[VTIME] = 10;
    
    //  This should be settable
    if(cfsetspeed(&portTermios, B230400) == -1) {
        NSLog(@"Cannot set terminal baud rate: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }

    if(tcsetattr(serialDescriptor, TCSANOW, &portTermios) == -1) {
        NSLog(@"Cannot set terminal attributes: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    //  Initialize the DV3K
    bytes = write(serialDescriptor, &dv3k_reset, sizeof(dv3k_reset.header) + ntohs(dv3k_reset.header.payload_length) + 1);
    if(bytes == -1) {
        NSLog(@"Couldn't Reset DV3000: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }

    //  Wait for ready signal
    do {
        if([self readPacket:&responsePacket] == NO) return NO;
        if(i > 10) return NO;
        ++i;
    } while (responsePacket.start_byte != DV3000_START_BYTE ||
             responsePacket.header.packet_type != DV3000_TYPE_CONTROL ||
             responsePacket.payload.ctrl.field_id != DV3000_CONTROL_READY);
    
    bytes = write(serialDescriptor, &dv3k_prodid, sizeof(dv3k_prodid.header) + ntohs(dv3k_prodid.header.payload_length) + 1);
    if(bytes == -1) {
        NSLog(@"Couldn't query product id: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    if([self readPacket:&responsePacket] == NO)
        return NO;
    if(responsePacket.start_byte != DV3000_START_BYTE ||
       responsePacket.header.packet_type != DV3000_TYPE_CONTROL ||
       responsePacket.payload.ctrl.field_id != DV3000_CONTROL_PRODID) {
        NSLog(@"Couldn't read product ID\n");
        close(serialDescriptor);
        return NO;
    }
    
    self.productId = [NSString stringWithCString:responsePacket.payload.ctrl.data.prodid encoding:NSUTF8StringEncoding];
    
    bytes = write(serialDescriptor, &dv3k_vers, sizeof(dv3k_vers.header) + ntohs(dv3k_vers.header.payload_length) + 1);
    if(bytes == -1) {
        NSLog(@"Couldn't query version: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    if([self readPacket:&responsePacket] == NO)
        return NO;
    if(responsePacket.start_byte != DV3000_START_BYTE ||
       responsePacket.header.packet_type != DV3000_TYPE_CONTROL ||
       responsePacket.payload.ctrl.field_id != DV3000_CONTROL_VERSTRING) {
        NSLog(@"Couldn't version\n");
        close(serialDescriptor);
        return NO;
    }
    
    self.version = [NSString stringWithCString:responsePacket.payload.ctrl.data.version encoding:NSUTF8StringEncoding];
   
    NSLog(@"Product ID is %@\n", self.productId);
    NSLog(@"Version is %@\n", self.version);
    
    //  Set up the Vocoder
    
    bytes = write(serialDescriptor, &dv3k_ratep, sizeof(dv3k_ratep.header) + ntohs(dv3k_ratep.header.payload_length) + 1);
    if(bytes == -1) {
        NSLog(@"Couldn't send RATEP request: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    if([self readPacket:&responsePacket] == NO)
        return NO;
    if(responsePacket.start_byte != DV3000_START_BYTE ||
       responsePacket.header.packet_type != DV3000_TYPE_CONTROL ||
       responsePacket.payload.ctrl.field_id != DV3000_CONTROL_RATEP) {
        NSLog(@"Couldn't set RATEP\n");
        close(serialDescriptor);
        return NO;
    }
    
    unsigned long mics = 300UL;
    if(ioctl(serialDescriptor, IOSSDATALAT, &mics) == -1) {
        NSLog(@"Cannot set data latency: %s\n", strerror(errno));
    }
    
    NSLog(@"DV3000 is now set up\n");
    
    portTermios.c_cc[VTIME] = 0;
    if(tcsetattr(serialDescriptor, TCSANOW, &portTermios) == -1) {
        NSLog(@"Cannot set terminal attributes: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    if(fcntl(serialDescriptor, F_SETFL, O_NONBLOCK | O_NDELAY) == -1) {
        NSLog(@"Couldn't set O_NONBLOCK: %s\n", strerror(errno));
    }
    
    /* if(fcntl(serialDescriptor, F_SETFL, O_NDELAY) == -1) {
        NSLog(@"Couldn't set O_NDELAY: %s\n", strerror(errno));
    } */
    
    // dispatch_queue_t mainQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    DMYDV3KVocoder __weak *weakSelf = self;
    NSLog(@"Inital Weak Self is %@\n", weakSelf);
    dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, serialDescriptor, 0, dispatchQueue);
    struct dv3k_packet *dataPacket;
    dataPacket = malloc(sizeof(struct dv3k_packet));
    dispatch_source_set_event_handler(dispatchSource, ^{
        char *buffer;
        
        NSLog(@"%ld bytes waiting in buffer\n", dispatch_source_get_data(dispatchSource));
        buffer = malloc(dispatch_source_get_data(dispatchSource));
        read((int) dispatch_source_get_handle(dispatchSource), buffer, dispatch_source_get_data(dispatchSource));
        free(buffer);
        return;
        
        while([weakSelf readPacket:dataPacket] == YES) {
            switch(dataPacket->header.packet_type) {
                case DV3000_TYPE_CONTROL:
                    NSLog(@"DV3K Control Packet Received\n");
                    break;
                case DV3000_TYPE_AMBE:
                    NSLog(@"DV3K AMBE Packet Received\n");
                    break;
                case DV3000_TYPE_AUDIO:
                    // NSLog(@"DV3K Audio Packet Received\n");
                    break;
            }
        }
        
        /* ioctl(serialDescriptor, FIONREAD, &bytesWaiting);
        NSLog(@"%d bytes ending in buffer\n", bytesWaiting); */
    });
    
    dispatch_source_set_cancel_handler(dispatchSource, ^{ close(serialDescriptor); });
    
    dispatch_resume(dispatchSource);
    
    NSLog(@"Completed serial setup\n");
    
    return YES;
}

- (void) dealloc {
    NSLog(@"Deallocating the vocoder object\n");
}

- (void) decodeData:(NSData *) data {
    dispatch_async(dispatchQueue, ^{
        ssize_t bytes;

        memcpy(&dv3k_ambe.payload.ambe.data, [data bytes], sizeof(dv3k_ambe.payload.ambe.data));
        
        bytes = write(serialDescriptor, &dv3k_ambe, sizeof(dv3k_ambe.header) + ntohs(dv3k_ambe.header.payload_length) + 1);
        if(bytes == -1) {
            NSLog(@"Couldn't send AMBE packet: %s\n", strerror(errno));
            return;
        }
    
    /* char *packetBytes = (char *) &dv3k_ambe;
    NSMutableString *packetString = [[NSMutableString alloc] init];
    [packetString appendFormat:@"Sending Packet: "];
    for(int i = 0; i < sizeof(dv3k_ambe.header) + ntohs(dv3k_ambe.header.payload_length) + 1; ++i)
        [packetString appendFormat:@"%02hhx ", packetBytes[i] ];
    NSLog(@"%@\n", packetString); */
    });
}

- (void) findStartByte {
        ssize_t bytes;
    char input;
    do {

        
        bytes = read(serialDescriptor, &input, 1);
        if(bytes == -1) {
            NSLog(@"Couldn't byte from descriptor: %s\n", strerror(errno));
            return;
        }
        
        // NSLog(@"Got byte 0x%02x\n", input);

    } while (input != DV3000_START_BYTE);
}

-(void) processPacket {
    struct dv3k_packet responsePacket = {0};
    
    if([self readPacket:&responsePacket] == NO)
        return;
    
    /* if(responsePacket.start_byte != DV3000_START_BYTE) {
        NSLog(@"Received invalid DV3K packet\n");
        [self findStartByte];
        return;
    } */
    
    switch(responsePacket.header.packet_type) {
        case DV3000_TYPE_CONTROL:
            NSLog(@"DV3K Control Packet Received\n");
            break;
        case DV3000_TYPE_AMBE:
            NSLog(@"DV3K AMBE Packet Received\n");
            break;
        case DV3000_TYPE_AUDIO:
            NSLog(@"DV3K Audio Packet Received\n");
            break;
    }
}

@end

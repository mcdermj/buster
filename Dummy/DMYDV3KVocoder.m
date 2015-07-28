//
//  DMYDV3KVocoder.m
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

#import "DMYDV3KVocoder.h"

#import <termios.h>
#import <sys/ioctl.h>
#import <IOKit/serial/ioss.h>
#import <IOKit/usb/IOUSBLib.h>

#import "DMYDataEngine.h"

#define DV3K_TYPE_CONTROL 0x00
#define DV3K_TYPE_AMBE 0x01
#define DV3K_TYPE_AUDIO 0x02

static const unsigned char DV3K_START_BYTE   = 0x61;

static const unsigned char DV3K_CONTROL_RATEP  = 0x0A;
static const unsigned char DV3K_CONTROL_PRODID = 0x30;
static const unsigned char DV3K_CONTROL_VERSTRING = 0x31;
static const unsigned char DV3K_CONTROL_RESET = 0x33;
static const unsigned char DV3K_CONTROL_READY = 0x39;
static const unsigned char DV3K_CONTROL_CHANFMT = 0x15;

static const unsigned char DV3K_AMBE_FIELD_CMODE = 0x02;
static const unsigned char DV3K_AMBE_FIELD_TONE = 0x08;
static const unsigned char DV3K_AMBE_FIELD_CHAND = 0x01;

static const unsigned char DV3K_AUDIO_FIELD_SPEECHD = 0x00;

static const char ratep_values[12] = { 0x01, 0x30, 0x07, 0x63, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x48 };

//  The size of a dv3k header is the start byte, plus header size plus the payload length
#define dv3k_packet_size(a) (1 + sizeof((a).header) + ntohs((a).header.payload_length))

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
                short chanfmt;
            } data;
        } ctrl;
        struct {
            unsigned char field_id;
            unsigned char num_samples;
            short samples[160];
            unsigned char cmode_field_id;
            short cmode_value;
        } audio;
        struct {
            struct {
                unsigned char field_id;
                unsigned char num_bits;
                unsigned char data[9];
            } data;
            struct {
                unsigned char field_id;
                unsigned short value;
            } cmode;
            struct {
                unsigned char field_id;
                unsigned char tone;
                unsigned char amplitude;
            } tone;
        } ambe;
   } payload;
};
#pragma pack(pop)

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

NSString * const DMYVocoderDeviceChanged = @"DMYVocoderDeviceChanged";

@interface DMYDV3KVocoder () {
    int serialDescriptor;
    dispatch_queue_t dispatchQueue;
    dispatch_queue_t readDispatchQueue;
    dispatch_source_t dispatchSource;
    struct dv3k_packet dv3k_ambe;
    struct dv3k_packet dv3k_audio;
    struct dv3k_packet *responsePacket;
    enum {
        DV3K_STOPPED,
        DV3K_STARTED
    } status;
}

@property (nonatomic, readwrite, copy) NSString *productId;
@property (nonatomic, readwrite, copy) NSString *version;

- (BOOL) readPacket:(struct dv3k_packet *)packet;
- (BOOL) sendCtrlPacket:(struct dv3k_packet)packet expectResponse:(uint8)response;
- (void) processPacket;
@end

static bool isFTDIPort(io_object_t device) {
    io_object_t parent;
    io_object_t grandparent;
    NSNumber *USBVendorId;
    NSNumber *USBProductId;
    OSStatus kernResult;
    
    kernResult = IORegistryEntryGetParentEntry(device, kIOServicePlane, &parent);
    if(kernResult != KERN_SUCCESS) {
        NSLog(@"Couldn't get parent: %d\n", kernResult);
        return NO;
    }
    
    kernResult = IORegistryEntryGetParentEntry(parent, kIOServicePlane, &grandparent);
    if(kernResult != KERN_SUCCESS) {
        NSLog(@"Couldn't get grandparent: %d\n", kernResult);
        return NO;
    }
    
    USBVendorId = CFBridgingRelease(IORegistryEntryCreateCFProperty(grandparent, CFSTR(kUSBVendorID), kCFAllocatorDefault, 0));
    USBProductId = CFBridgingRelease(IORegistryEntryCreateCFProperty(grandparent, CFSTR(kUSBProductID), kCFAllocatorDefault, 0));
    IOObjectRelease(parent);
    IOObjectRelease(grandparent);
    
    return (USBVendorId.intValue == 0x0403 && USBProductId.intValue == 0x6015);
}

static void VocoderAdded(void *refCon, io_iterator_t iterator) {
    //  This is needed to disarm the iterator.  Otherwise we won't get any more events.
    while(IOIteratorNext(iterator));
    
    //  We need to wait 5ms for the device system to catch up, otherwise the io files won't all be created yet and the device won't open.
    //  If there's only one possible port, we'll try it and see if it's a DV3K.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5ull * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        NSArray *ports = [DMYDV3KVocoder ports];
        if(ports.count == 1) {
            [DMYDataEngine sharedInstance].vocoder.serialPort = ports[0];
            [[DMYDataEngine sharedInstance].vocoder start];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:DMYVocoderDeviceChanged object: nil];
    });
}

static void VocoderRemoved(void *refCon, io_iterator_t iterator) {
    io_object_t serialDevice;
    
    //  If one of the devices that's being removed is the active device, we need to shut down the vocoder engine.
    while((serialDevice = IOIteratorNext(iterator))) {
        NSString *deviceFile = CFBridgingRelease(IORegistryEntryCreateCFProperty(serialDevice, CFSTR(kIOCalloutDeviceKey), kCFAllocatorDefault, 0));
        if([deviceFile isEqualToString:[DMYDataEngine sharedInstance].vocoder.serialPort])
            dispatch_async(dispatch_get_main_queue(), ^{
                [[DMYDataEngine sharedInstance].vocoder stop];
            });
    };
    
    [[NSNotificationCenter defaultCenter] postNotificationName:DMYVocoderDeviceChanged object: nil];
}


@implementation DMYDV3KVocoder

+ (void) initialize {
    mach_port_t masterPort;
    NSMutableDictionary *matchingDict;
    CFRunLoopSourceRef runLoopSource;
    kern_return_t kernReturn;
    io_iterator_t deviceIterator;
    
    kernReturn = IOMasterPort(MACH_PORT_NULL, &masterPort);
    if(kernReturn != KERN_SUCCESS) {
        NSLog(@"Cannot get mach port\n");
        return;
    }
    
    matchingDict = CFBridgingRelease(IOServiceMatching(kIOSerialBSDServiceValue));
    if(matchingDict == NULL) {
        NSLog(@"IOServiceMatching returned a NULL dictionary.\n");
    } else {
        [matchingDict setValue:[NSString stringWithCString:kIOSerialBSDRS232Type encoding:NSUTF8StringEncoding]
                          forKey:[NSString stringWithCString:kIOSerialBSDTypeKey encoding:NSUTF8StringEncoding]];
    }
    
    IONotificationPortRef gNotifyPort = IONotificationPortCreate(masterPort);
    runLoopSource = IONotificationPortGetRunLoopSource(gNotifyPort);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    
    matchingDict = (NSMutableDictionary *) CFRetain((__bridge CFTypeRef)(matchingDict));
    matchingDict = (NSMutableDictionary *) CFRetain((__bridge CFTypeRef)(matchingDict));
    
    IOServiceAddMatchingNotification(gNotifyPort, kIOFirstMatchNotification, (__bridge CFDictionaryRef)(matchingDict), VocoderAdded, NULL, &deviceIterator);
    // Clean out the device iterator so the notification will arm.
    while(IOIteratorNext(deviceIterator));
    
    IOServiceAddMatchingNotification(gNotifyPort, kIOTerminatedNotification, (__bridge CFDictionaryRef)(matchingDict), VocoderRemoved, NULL, &deviceIterator);
    // Clean out the device iterator so the notification will arm.
    while(IOIteratorNext(deviceIterator));
    
    mach_port_deallocate(mach_task_self(), masterPort);
}

- (id) init {
    self = [super init];
    
    if(self) {
        dv3k_ambe.start_byte = DV3K_START_BYTE;
        dv3k_ambe.header.packet_type = DV3K_TYPE_AMBE;
        dv3k_ambe.header.payload_length = htons(sizeof(dv3k_ambe.payload.ambe.data));
        dv3k_ambe.payload.ambe.data.field_id = DV3K_AMBE_FIELD_CHAND;
        dv3k_ambe.payload.ambe.data.num_bits = sizeof(dv3k_ambe.payload.ambe.data.data) * 8;
        
        dv3k_audio.start_byte = DV3K_START_BYTE;
        dv3k_audio.header.packet_type = DV3K_TYPE_AUDIO;
        dv3k_audio.header.payload_length = htons(sizeof(dv3k_ambe.payload.audio));
        dv3k_audio.payload.audio.field_id = DV3K_AUDIO_FIELD_SPEECHD;
        dv3k_audio.payload.audio.num_samples = sizeof(dv3k_audio.payload.audio.samples) / sizeof(short);
        dv3k_audio.payload.audio.cmode_field_id = 0x02;
        dv3k_audio.payload.audio.cmode_value = htons(0x4000);
        
        
        dispatch_queue_attr_t dispatchQueueAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
        dispatchQueue = dispatch_queue_create("net.nh6z.Dummy.SerialIO.Write", dispatchQueueAttr);
        readDispatchQueue = dispatch_queue_create("net.nh6z.Dummy.SerialIO.Read", dispatchQueueAttr);
        dispatchSource = NULL;
        
        responsePacket = calloc(1, sizeof(struct dv3k_packet));
        
        self.speed = 0;
        self.serialPort = @"";
        
        self.beep = YES;
        
        serialDescriptor = 0;
        
        status = DV3K_STOPPED;
        
    }
    
    return self;
}

- (void) setSpeed:(long)speed {
    if(_speed == speed) return;
    
    _speed = speed;
    
    if(status == DV3K_STARTED) {
        [self stop];
        [self start];
    }
}

- (void) setSerialPort:(NSString *)serialPort {
    if([serialPort isEqualToString:_serialPort]) return;
    
    _serialPort = serialPort;
    
    if(status == DV3K_STARTED) {
        [self stop];
        [self start];
    }
}

+ (NSArray *) ports {
    kern_return_t kernResult;
    mach_port_t masterPort;
    NSDictionary *classesToMatch;
    io_iterator_t matchingServices;
    io_object_t serialDevice;
    NSMutableArray *deviceArray = [NSMutableArray arrayWithCapacity:1];
    
    kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
    if(kernResult != KERN_SUCCESS) {
        NSLog(@"Couldn't get master port: %d\n", kernResult);
        return nil;
    }
    
    classesToMatch = CFBridgingRelease(IOServiceMatching(kIOSerialBSDServiceValue));
    if(classesToMatch == NULL) {
        NSLog(@"IOServiceMatching returned a NULL dictionary.\n");
    } else {
        [classesToMatch setValue:[NSString stringWithCString:kIOSerialBSDRS232Type encoding:NSUTF8StringEncoding]
                          forKey:[NSString stringWithCString:kIOSerialBSDTypeKey encoding:NSUTF8StringEncoding]];
    }
    
    kernResult = IOServiceGetMatchingServices(masterPort, CFBridgingRetain(classesToMatch), &matchingServices);
    if(kernResult != KERN_SUCCESS) {
        NSLog(@"Couldn't get matching services: %d\n", kernResult);
        return nil;
    }
    
    while((serialDevice = IOIteratorNext(matchingServices))) {
        NSString *deviceFile = CFBridgingRelease(IORegistryEntryCreateCFProperty(serialDevice, CFSTR(kIOCalloutDeviceKey), kCFAllocatorDefault, 0));
        
        if(deviceFile && isFTDIPort(serialDevice)) {
            [deviceArray addObject:deviceFile];
        }
    }
    
    IOObjectRelease(matchingServices);
    
    mach_port_deallocate(mach_task_self(), masterPort);

    return [NSArray arrayWithArray:deviceArray];
}

- (BOOL) readPacket:(struct dv3k_packet *)packet {
    ssize_t bytes;
    size_t bytesLeft;
    
    packet->start_byte = 0x00;
    
    int i;
    for(i = 0; i < sizeof(struct dv3k_packet); ++i) {
    bytes = read(serialDescriptor, packet, 1);
        if(bytes == -1 && errno != EAGAIN) {
            NSLog(@"Couldn't read start byte: %s\n", strerror(errno));
            return NO;
        }
        if(packet->start_byte == DV3K_START_BYTE)
            break;
    }
    if(packet->start_byte != DV3K_START_BYTE)
        return NO;
    
    if(i > 0)
        NSLog(@"Took %d tries to find the start byte", i);
    
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

    if(status != DV3K_STOPPED) {
        NSLog(@"Called sendCtrlPacket: when started\n");
        return NO;
    }
    
    if(write(serialDescriptor, &packet, dv3k_packet_size(packet)) == -1) {
        NSLog(@"Couldn't write control packet\n");
        return NO;
    }
    
    if([self readPacket:responsePacket] == NO)
        return NO;
    
    if(responsePacket->start_byte != DV3K_START_BYTE ||
       responsePacket->header.packet_type != DV3K_TYPE_CONTROL ||
       responsePacket->payload.ctrl.field_id != response) {
        NSLog(@"Couldn't get control response\n");
        return NO;
    }

    return YES;
}

- (BOOL) start {
    struct termios portTermios;
    
    if(status != DV3K_STOPPED) {
        NSLog(@"DV3K is not closed\n");
        return YES;
    }
    
    self.version = @"";
    self.productId = @"";
    
    if(self.serialPort == nil || [self.serialPort isEqualToString:@""])
        return NO;
    
    serialDescriptor = open([self.serialPort cStringUsingEncoding:NSUTF8StringEncoding], O_RDWR | O_NOCTTY);
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
    portTermios.c_cflag    &= ~(CSIZE | CSTOPB | PARENB);
    portTermios.c_cflag    |= CS8 | CRTSCTS;
    portTermios.c_oflag    &= ~(OPOST);
    portTermios.c_cc[VMIN] = 0;
    portTermios.c_cc[VTIME] = 5;
    
    if(tcsetattr(serialDescriptor, TCSANOW, &portTermios) == -1) {
        NSLog(@"Cannot set terminal attributes: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    if(ioctl(serialDescriptor, IOSSIOSPEED, &_speed) == -1) {
        NSLog(@"Cannot set terminal baud rate: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    //  Initialize the DV3K
    struct dv3k_packet ctrlPacket = {
        .start_byte = DV3K_START_BYTE,
        .header.packet_type = DV3K_TYPE_CONTROL,
        .header.payload_length = htons(1),
        .payload.ctrl.field_id = DV3K_CONTROL_RESET
    };
    if(![self sendCtrlPacket:ctrlPacket expectResponse:DV3K_CONTROL_READY]) {
        NSLog(@"Couldn't Reset DV3000: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    ctrlPacket.payload.ctrl.field_id = DV3K_CONTROL_PRODID;
    if(![self sendCtrlPacket:ctrlPacket expectResponse:DV3K_CONTROL_PRODID]) {
        NSLog(@"Couldn't query product id: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    NSString *tmpProductId = [NSString stringWithCString:responsePacket->payload.ctrl.data.prodid encoding:NSUTF8StringEncoding];
    
    ctrlPacket.payload.ctrl.field_id = DV3K_CONTROL_VERSTRING;
    if(![self sendCtrlPacket:ctrlPacket expectResponse:DV3K_CONTROL_VERSTRING]) {
        NSLog(@"Couldn't query version: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
        
    }
    NSString *tmpVersion = [NSString stringWithCString:responsePacket->payload.ctrl.data.version encoding:NSUTF8StringEncoding];
    
    
    //  Set up the Vocoder
    ctrlPacket.header.payload_length = htons(sizeof(ctrlPacket.payload.ctrl.data.ratep) + 1);
    ctrlPacket.payload.ctrl.field_id = DV3K_CONTROL_RATEP;
    memcpy(ctrlPacket.payload.ctrl.data.ratep, ratep_values, sizeof(ratep_values));
    if([self sendCtrlPacket:ctrlPacket expectResponse:DV3K_CONTROL_RATEP] == NO) {
        NSLog(@"Couldn't send RATEP request: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    ctrlPacket.header.payload_length = htons(sizeof(ctrlPacket.payload.ctrl.data.chanfmt) + 1);
    ctrlPacket.payload.ctrl.field_id = DV3K_CONTROL_CHANFMT;
    ctrlPacket.payload.ctrl.data.chanfmt = htons(0x0001);
    if([self sendCtrlPacket:ctrlPacket expectResponse:DV3K_CONTROL_CHANFMT] == NO) {
        NSLog(@"Couldn't send CHANFMT request: %s\n", strerror(errno));
        close(serialDescriptor);
        return NO;
    }
    
    NSLog(@"DV3000 is now set up\n");
    
    if(fcntl(serialDescriptor, F_SETFL, O_NONBLOCK | O_NDELAY) == -1) {
        NSLog(@"Couldn't set O_NONBLOCK: %s\n", strerror(errno));
    }
    
    //dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) serialDescriptor, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) serialDescriptor, 0, readDispatchQueue);
    DMYDV3KVocoder __weak *weakSelf = self;
    dispatch_source_set_event_handler(dispatchSource, ^{
        [weakSelf processPacket];
    });
    
    dispatch_source_set_cancel_handler(dispatchSource, ^{
        if(serialDescriptor) {
            close(serialDescriptor);
            serialDescriptor = 0;
        }
    });
    
    dispatch_resume(dispatchSource);
    
    NSLog(@"Completed serial setup\n");
    
    self.productId = tmpProductId;
    self.version = tmpVersion;
    
    NSLog(@"Product ID is %@\n", self.productId);
    NSLog(@"Version is %@\n", self.version);
    
    status = DV3K_STARTED;
    
    return YES;
}

- (void) stop {
    if(status != DV3K_STARTED) {
        NSLog(@"DV3K isn't started\n");
        return;
    }
    
    dispatch_source_cancel(dispatchSource);
    
    self.productId = @"";
    self.version = @"";
    
    status = DV3K_STOPPED;
}

- (void) dealloc {
    free(responsePacket);
}

- (void) decodeData:(void *) data lastPacket:(BOOL)last {
    if(status != DV3K_STARTED)
        return;
    
    memcpy(&dv3k_ambe.payload.ambe.data.data, data, sizeof(dv3k_ambe.payload.ambe.data.data));
    
    dispatch_async(dispatchQueue, ^{
        ssize_t bytes;
        
        bytes = write(serialDescriptor, &dv3k_ambe, dv3k_packet_size(dv3k_ambe));
        if(bytes == -1) {
            NSLog(@"Couldn't send AMBE packet: %s\n", strerror(errno));
            return;
        }
        
        if(bytes == 0) {
            NSLog(@"No bytes written to serial port!");
        }
        
        if(last && self.beep) {
            for(int i = 0; i < 5; ++i) {
                bytes = write(serialDescriptor, &bleepPacket, dv3k_packet_size(bleepPacket));
                if(bytes == -1) {
                    NSLog(@"Couldn't write bleep packet: %s\n", strerror(errno));
                    return;
                }
            }
            
            //  Write a silence packet to clean out the chain
            bytes = write(serialDescriptor, &silencePacket, dv3k_packet_size(silencePacket));
            if(bytes == -1) {
                NSLog(@"Couldn't write silence packet: %s\n", strerror(errno));
                return;
            }
        }
    });
}

- (void) encodeData:(void *)  data lastPacket:(BOOL)last {
    // XXX We shouldn't have to free the data.
    if(status != DV3K_STARTED) {
        free(data);
        return;
    }
    
    dispatch_async(dispatchQueue, ^{
        ssize_t bytes;
        
        memcpy(&dv3k_audio.payload.audio.samples, data, sizeof(dv3k_audio.payload.audio.samples));
        if(last)
            dv3k_audio.payload.audio.cmode_value = htons(0x4000);
        else
            dv3k_audio.payload.audio.cmode_value = 0x0000;
                
        bytes = write(serialDescriptor, &dv3k_audio, dv3k_packet_size(dv3k_audio));
        if(bytes == -1) {
            NSLog(@"Couldn't send audio packet: %s\n", strerror(errno));
            return;
        }
        
        free(data);
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
           //  NSLog(@"DV3K AMBE Packet Received payload length %d with cmode = 0x%04X\n", ntohs(responsePacket->header.payload_length), ntohs(responsePacket->payload.ambe.cmode.value));
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
            
            [[DMYDataEngine sharedInstance].network sendAMBE:responsePacket->payload.ambe.data.data lastPacket:last];
            
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

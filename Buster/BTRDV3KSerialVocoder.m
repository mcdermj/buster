//
//  BTRDV3KSerialVocoder.m
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


#import "BTRDV3KSerialVocoder.h"

#import <termios.h>
#import <sys/ioctl.h>

#import <IOKit/serial/ioss.h>
#import <IOKit/usb/IOUSBLib.h>

#import "BTRDV3KPacket.h"
#import "BTRDataEngine.h"
#import "BTRSerialVocoderViewController.h"

#pragma mark - Device removal and insertion

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
    BTRDV3KSerialVocoder *self = (__bridge BTRDV3KSerialVocoder *) refCon;
    //  This is needed to disarm the iterator.  Otherwise we won't get any more events.
    while(IOIteratorNext(iterator));
    
    //  We need to wait 5ms for the device system to catch up, otherwise the io files won't all be created yet and the device won't open.
    //  If there's only one possible port, we'll try it and see if it's a DV3K.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5ull * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        NSArray *ports = [BTRDV3KSerialVocoder ports];
        if(ports.count == 1) {
            self.serialPort = ports[0];
            [self start];
        }
        
        if(self.configurationViewController)
            [(BTRSerialVocoderViewController *)self.configurationViewController refreshDevices];
    });
}

static void VocoderRemoved(void *refCon, io_iterator_t iterator) {
    BTRDV3KSerialVocoder *self = (__bridge BTRDV3KSerialVocoder *) refCon;
    io_object_t serialDevice;
    
    //  If one of the devices that's being removed is the active device, we need to shut down the vocoder engine.
    while((serialDevice = IOIteratorNext(iterator))) {
        NSString *deviceFile = CFBridgingRelease(IORegistryEntryCreateCFProperty(serialDevice, CFSTR(kIOCalloutDeviceKey), kCFAllocatorDefault, 0));
        if([deviceFile isEqualToString:self.serialPort])
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stop];
            });
    };
 
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5ull * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if(self.configurationViewController)
            [(BTRSerialVocoderViewController *)self.configurationViewController refreshDevices];
    });
}

@interface BTRDV3KSerialVocoder () {
    IONotificationPortRef gNotifyPort;
    io_iterator_t deviceAddedIterator;
    io_iterator_t deviceRemovedIterator;
    BTRSerialVocoderViewController *_configurationViewController;
}

@end

@implementation BTRDV3KSerialVocoder

+(void) load {
    [BTRDataEngine registerVocoderDriver:self];
}

#pragma mark - Accessors

- (void) setSpeed:(long)speed {
    if(_speed == speed) return;
    
    _speed = speed;
    
    if(self.started)
        [self stop];
    
    [self start];
}

- (void) setSerialPort:(NSString *)serialPort {
    if([serialPort isEqualToString:_serialPort]) return;
    
    _serialPort = serialPort;
    
    if(self.started)
        [self stop];
    
    [self start];
}


+(NSString *) driverName {
    return @"Thumb DV";
}

-(NSViewController *) configurationViewController {
    if(!_configurationViewController) {
        _configurationViewController = [[BTRSerialVocoderViewController alloc] init];
        _configurationViewController.driver = self;
     }
    return _configurationViewController;
}

#pragma mark - Port enumeration

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

- (id) init {
    self = [super init];
    if(self) {
        _speed = [[NSUserDefaults standardUserDefaults] integerForKey:@"DV3KSerialVocoderSpeed"];
        _serialPort = [[NSUserDefaults standardUserDefaults] stringForKey:@"DV3KSerialVocoderPort"];
        if(!_serialPort) {
            NSArray *ports = [BTRDV3KSerialVocoder ports];
            if(ports.count == 1)
                _serialPort = ports[0];
            else
                _serialPort = @"";
        }
        
        mach_port_t masterPort;
        NSMutableDictionary *matchingDict;
        CFRunLoopSourceRef runLoopSource;
        kern_return_t kernReturn;
        
        kernReturn = IOMasterPort(MACH_PORT_NULL, &masterPort);
        if(kernReturn != KERN_SUCCESS) {
            NSLog(@"Cannot get mach port\n");
            return nil;
        }
        
        matchingDict = CFBridgingRelease(IOServiceMatching(kIOSerialBSDServiceValue));
        if(matchingDict == NULL) {
            NSLog(@"IOServiceMatching returned a NULL dictionary.\n");
        } else {
            [matchingDict setValue:[NSString stringWithCString:kIOSerialBSDRS232Type encoding:NSUTF8StringEncoding]
                            forKey:[NSString stringWithCString:kIOSerialBSDTypeKey encoding:NSUTF8StringEncoding]];
        }
        
        gNotifyPort = IONotificationPortCreate(masterPort);
        runLoopSource = IONotificationPortGetRunLoopSource(gNotifyPort);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        
        matchingDict = (NSMutableDictionary *) CFRetain((__bridge CFTypeRef)(matchingDict));
        matchingDict = (NSMutableDictionary *) CFRetain((__bridge CFTypeRef)(matchingDict));
        
        IOServiceAddMatchingNotification(gNotifyPort, kIOFirstMatchNotification, (__bridge CFDictionaryRef)(matchingDict), VocoderAdded, (__bridge void *)(self), &deviceAddedIterator);
        // Clean out the device iterator so the notification will arm.
        while(IOIteratorNext(deviceAddedIterator));
        
        IOServiceAddMatchingNotification(gNotifyPort, kIOTerminatedNotification, (__bridge CFDictionaryRef)(matchingDict), VocoderRemoved, (__bridge void *)(self), &deviceRemovedIterator);
        // Clean out the device iterator so the notification will arm.
        while(IOIteratorNext(deviceRemovedIterator));
        
        mach_port_deallocate(mach_task_self(), masterPort);
        
        BTRDV3KSerialVocoder __weak *weakSelf = self;
        [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock: ^(NSNotification *notification) {
                                                          NSLog(@"User defaults changing");
                                                          weakSelf.speed = [[NSUserDefaults standardUserDefaults] integerForKey:@"DV3KSerialVocoderSpeed"];
                                                          NSString *serialPort =[[NSUserDefaults standardUserDefaults] stringForKey:@"DV3KSerialVocoderPort"];
                                                          if(serialPort)
                                                              weakSelf.serialPort = serialPort;
                                                      }];
    }
    return self;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSUserDefaultsDidChangeNotification object:nil];
    IOObjectRelease(deviceAddedIterator);
    IOObjectRelease(deviceRemovedIterator);
    IONotificationPortDestroy(gNotifyPort);
}

- (void) setProductId:(NSString *)productId {
    super.productId = productId;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        ((BTRSerialVocoderViewController *)self.configurationViewController).productId.stringValue = productId;
    });
}

- (void) setVersion:(NSString *)version {
    super.version = version;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        ((BTRSerialVocoderViewController *)self.configurationViewController).version.stringValue = version;
    });
}

- (BOOL) openPort {
    struct termios portTermios;
    
    if(self.serialPort == nil || [self.serialPort isEqualToString:@""])
        return NO;
    
    NSLog(@"Opening %@ at %ld baud", self.serialPort, self.speed);
    
    self.descriptor = open([self.serialPort cStringUsingEncoding:NSUTF8StringEncoding], O_RDWR | O_NOCTTY);
    if(self.descriptor == -1) {
        NSLog(@"Error opening DV3000 Serial Port: %s\n", strerror(errno));
        return NO;
    }
    
    if(tcgetattr(self.descriptor, &portTermios) == -1) {
        NSLog(@"Cannot get terminal attributes: %s\n", strerror(errno));
        close(self.descriptor);
        return NO;
    }
    
    portTermios.c_lflag    &= ~(ECHO | ECHOE | ICANON | IEXTEN | ISIG);
    portTermios.c_iflag    &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON | IXOFF | IXANY);
    portTermios.c_cflag    &= ~(CSIZE | CSTOPB | PARENB);
    portTermios.c_cflag    |= CS8 | CRTSCTS;
    portTermios.c_oflag    &= ~(OPOST);
    portTermios.c_cc[VMIN] = 0;
    portTermios.c_cc[VTIME] = 1;
    
    if(tcsetattr(self.descriptor, TCSANOW, &portTermios) == -1) {
        NSLog(@"Cannot set terminal attributes: %s\n", strerror(errno));
        close(self.descriptor);
        return NO;
    }
    
    if(ioctl(self.descriptor, IOSSIOSPEED, &_speed) == -1) {
        NSLog(@"Cannot set terminal baud rate: %s\n", strerror(errno));
        close(self.descriptor);
        return NO;
    }
    
    return YES;
}

- (BOOL) setNonblocking {
    if(fcntl(self.descriptor, F_SETFL, O_NONBLOCK | O_NDELAY) == -1) {
        NSLog(@"Couldn't set O_NONBLOCK: %s\n", strerror(errno));
        return NO;
    }
    
    return YES;
}

- (void) closePort {
    if(self.descriptor) {
        close(self.descriptor);
        self.descriptor = 0;
    }
}

#pragma mark - IO Functions

- (BOOL) readPacket:(struct dv3k_packet *)packet {
    ssize_t bytes;
    size_t bytesLeft;
    
    packet->start_byte = 0x00;
    
    int i;
    int tries = self.started ? sizeof(struct dv3k_packet) : 10;
    for(i = 0; i < tries; ++i) {
        bytes = read(self.descriptor, packet, 1);
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
        bytes = read(self.descriptor, ((uint8_t *) &packet->header) + sizeof(packet->header) - bytesLeft, bytesLeft);
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
        bytes = read(self.descriptor, ((uint8_t *) &packet->payload) + (ntohs(packet->header.payload_length) - bytesLeft), bytesLeft);
        if(bytes == -1) {
            if(errno == EAGAIN) continue;
            NSLog(@"Couldn't read payload: %s\n", strerror(errno));
            return NO;
        }
        
        bytesLeft -= (size_t) bytes;
    }
    
    return YES;
}

- (BOOL) writePacket:(const struct dv3k_packet *)packet {
    ssize_t bytes;
    size_t bytesLeft;
    
    bytesLeft = dv3k_packet_size(*packet);
    while(bytesLeft > 0) {
        bytes = write(self.descriptor, (((uint8_t *) packet) + dv3k_packet_size(*packet)) - bytesLeft, bytesLeft);
        if(bytes < 0) {
            if(errno == EAGAIN) continue;
            NSLog(@"Couldn't read header: %s\n", strerror(errno));
            return NO;
        }
        
        bytesLeft -= (size_t) bytes;
        
    }
    return YES;
}

@end

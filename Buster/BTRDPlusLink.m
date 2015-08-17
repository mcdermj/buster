//
//  BTRDPlusLink.m
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


#import "BTRDPlusLink.h"

#import <arpa/inet.h>
#import <sys/ioctl.h>

#import "BTRDPlusAuthenticator.h"


struct dplus_packet {
    unsigned short length;
    char type;
    char padding;
    union {
        char link;
        char ack[4];
        struct {
            char repeater[16];
            char magic[8];
        } linkModule;
    } payload;
} __attribute__((packed));

#define dplus_packet_size(a) ((a).length & 0x0FFF)

static const char DPLUS_TYPE_POLL = 0x00;
static const char DPLUS_TYPE_LINK = 0x18;
static const char DPLUS_TYPE_LINKMODULE = 0x04;

static const struct dplus_packet linkTemplate = {
    .length = 0x05,
    .type = DPLUS_TYPE_LINK,
    .padding = 0x00,
    .payload.link = 0x01
};

static const struct dplus_packet unlinkTemplate = {
    .length = 0x05,
    .type = DPLUS_TYPE_LINK,
    .padding = 0x00,
    .payload.link = 0x00
};

static const struct dplus_packet linkModuleTemplate = {
    .length = 0xC01C,
    .type = DPLUS_TYPE_LINKMODULE,
    .padding = 0x00,
    .payload.linkModule.repeater = "NH6Z",
    .payload.linkModule.magic = "DV019999"
};

static const struct dplus_packet pollPacket = {
    .length = 0x6003,
    .type = DPLUS_TYPE_POLL
};


@interface BTRDPlusLink ()

@property (nonatomic, readwrite, getter=isLinked) BOOL linked;
@property (nonatomic, copy) NSString *target;
@property (nonatomic) int socket;
@property (nonatomic) dispatch_source_t dispatchSource;
@property (nonatomic) dispatch_queue_t writeQueue;

- (void) link;

@end

@implementation BTRDPlusLink

- (id) initWithTarget:(NSString *)target {
    self = [super init];
    if(self) {
        _target = [target copy];
        dispatch_queue_attr_t dispatchQueueAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
        _writeQueue = dispatch_queue_create("net.nh6z.Dummy.DPlusWrite", dispatchQueueAttr);

        [self link];
    }
    
    return self;
}

- (void) sendPacket:(const struct dplus_packet)packet {
    dispatch_async(self.writeQueue, ^{
        size_t bytesSent = send(self.socket, &packet, dplus_packet_size(packet), 0);
        if(bytesSent == -1) {
            NSLog(@"Couldn't write link request: %s", strerror(errno));
            return;
        }
        if(bytesSent != dplus_packet_size(packet)) {
            NSLog(@"Short write on link");
            return;
        }
    });
}

- (void)processLinkPacket:(struct dplus_packet *)packet {
    switch(packet->type) {
        case DPLUS_TYPE_LINK:
            switch(packet->payload.link) {
                case 0x00:
                    NSLog(@"DPlus reports unlinked");
                    self.linked = NO;
                    break;
                case 0x01: {
                    NSLog(@"DPlus reports linked");
                    struct dplus_packet linkPacket = { 0 };
                    memcpy(&linkPacket, &linkModuleTemplate, sizeof(linkPacket));
                
                    memcpy(linkPacket.payload.linkModule.repeater, [[BTRDPlusAuthenticator sharedInstance].authCall cStringUsingEncoding:NSUTF8StringEncoding], [BTRDPlusAuthenticator sharedInstance].authCall.length);
                    [self sendPacket:linkPacket];
                    break;
                }
                default:
                    NSLog(@"Received unknown value for link packet: 0x%02X", packet->payload.link);
                    break;
            }
            break;
        case DPLUS_TYPE_LINKMODULE:
            if(!strncmp(packet->payload.linkModule.repeater, "OKRW", 4)) {
                NSLog(@"Received ACK from repeater, we are now linked");
                self.linked = YES;
            } else if(!strncmp(packet->payload.linkModule.repeater, "BUSY", 4)) {
                NSLog(@"Received NACK from repeater, link failed");
                [self unlink];
            } else {
                NSLog(@"Unknown link packet received");
            }
            break;
        default:
            NSLog(@"Received unknown packet type 0x%02X", packet->type);
            break;
    }
}

- (void)processPollPacket:(struct dplus_packet *)packet {
    if(packet->type != DPLUS_TYPE_POLL) {
        NSLog(@"Received invalid poll packet");
        return;
    }
    
    NSLog(@"Poll received from reflector");
    [self sendPacket:pollPacket];
}


- (void) link {
    self.socket = socket(PF_INET, SOCK_DGRAM, 0);
    if(self.socket == -1) {
        NSLog(@"Error opening socket: %s\n", strerror(errno));
        return;
    }
    
    int one = 1;
    if(setsockopt(self.socket, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one))) {
        NSLog(@"Couldn't set socket to SO_REUSEADDR: %s\n", strerror(errno));
        return;
    }
    
    if(fcntl(self.socket, F_SETFL, O_NONBLOCK) == -1) {
        NSLog(@"Couldn't set socket to nonblocking: %s\n", strerror(errno));
        return;
    }
   
    struct sockaddr_in addr = {
        .sin_len = sizeof(struct sockaddr_in),
        .sin_family = AF_INET,
        .sin_port = htons(20001),
        .sin_addr.s_addr = INADDR_ANY
    };
    
    if(bind(self.socket, (const struct sockaddr *) &addr, (socklen_t) sizeof(addr))) {
        NSLog(@"Couldn't bind gateway socket: %s\n", strerror(errno));
        return;
    }

    NSString *targetReflector = [[self.target substringWithRange:NSMakeRange(0, 7)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSUInteger reflectorIndex = [[BTRDPlusAuthenticator sharedInstance].reflectorList indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [obj[@"name"] isEqualToString:targetReflector];
    }];
    if(reflectorIndex == NSNotFound) {
        NSLog(@"Couldn't find reflector %@", self.target);
        return;
    }
    addr.sin_addr.s_addr = inet_addr([[BTRDPlusAuthenticator sharedInstance].reflectorList[reflectorIndex][@"address"] cStringUsingEncoding:NSUTF8StringEncoding]);
    
    NSLog(@"Linking to %@ at %@", self.target, [BTRDPlusAuthenticator sharedInstance].reflectorList[reflectorIndex][@"address"]);
    
    if(connect(self.socket, (const struct sockaddr *) &addr, (socklen_t) sizeof(addr))) {
        NSLog(@"Couldn't connect socket: %s\n", strerror(errno));
        return;
    }
    
    NSLog(@"Link Connection Complete");
    
    dispatch_queue_t mainQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    self.dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) self.socket, 0, mainQueue);
    BTRDPlusLink __weak *weakSelf = self;
    dispatch_source_set_event_handler(self.dispatchSource, ^{
        struct dplus_packet incomingPacket = { 0 };
        size_t packetSize;
        
        do {
            packetSize = recv(weakSelf.socket, &incomingPacket, sizeof(struct dplus_packet), 0);
            if(packetSize == -1) {
                if(errno == EAGAIN)
                    break;
                NSLog(@"Couldn't read DPlus packet: %s", strerror(errno));
                return;
            }
            
            switch(incomingPacket.length & 0xF000) {
                case 0x8000:
                    NSLog(@"Data packet processing here");
                    break;
                case 0x6000:
                    [weakSelf processPollPacket:&incomingPacket];
                    break;
                case 0xC000:
                case 0x0000:
                    [weakSelf processLinkPacket:&incomingPacket];
                    break;
                default:
                    NSLog(@"Invalid flag byte 0x%02X", incomingPacket.length & 0xF000);
                    break;
            }
        } while(packetSize > 0);
    });
    dispatch_resume(self.dispatchSource);
    
    [self sendPacket:linkTemplate];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"Unlinking after 10 seconds");
        [weakSelf unlink];
    });
}

-(void)unlink {
    BTRDPlusLink __weak *weakSelf = self;
    int tries = 0;

    do {
        dispatch_sync(self.writeQueue, ^{
            [weakSelf sendPacket:unlinkTemplate];
        });
        if(tries++ > 10)
            break;
    } while(self.isLinked);
}

- (void) dealloc  {
    // XXX Unlink from reflector here.
}

@end

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

@interface BTRDPlusLink ()

@property (nonatomic, readwrite, getter=isLinked) BOOL linked;
@property (nonatomic, copy) NSString *target;
@property (nonatomic) int socket;
@property (nonatomic) dispatch_source_t dispatchSource;

- (void) link;

@end

@implementation BTRDPlusLink

- (id) initWithTarget:(NSString *)target {
    self = [super init];
    if(self) {
        _target = [target copy];
    }
    
    return self;
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
    
    NSUInteger reflectorIndex = [[BTRDPlusAuthenticator sharedInstance].reflectorList indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [obj isEqualToString:self.target];
    }];
    if(reflectorIndex == NSNotFound) {
        NSLog(@"Couldn't find reflector %@", self.target);
        return;
    }
    addr.sin_addr.s_addr = inet_addr([[BTRDPlusAuthenticator sharedInstance].reflectorList[reflectorIndex][@"address"] cStringUsingEncoding:NSUTF8StringEncoding]);
    
    if(connect(self.socket, (const struct sockaddr *) &addr, (socklen_t) sizeof(addr))) {
        NSLog(@"Couldn't connect socket: %s\n", strerror(errno));
        return;
    }
    
    dispatch_queue_t mainQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    self.dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) self.socket, 0, mainQueue);
    // BTRDPlusLink __weak *weakSelf = self;
    dispatch_source_set_event_handler(self.dispatchSource, ^{
        /* size_t packetSize;
        
        do {
            packetSize = recv(gatewaySocket, &incomingPacket, sizeof(struct gatewayPacket), 0);
            if(packetSize == -1) {
                if(errno == EAGAIN) break;
                NSLog(@"Couldn't read packet: %s\n", strerror(errno));
                return;
            }
            
            [weakSelf processPacket:&incomingPacket];
        } while(packetSize > 0); */
    });
    
    dispatch_resume(self.dispatchSource);

}

- (void) dealloc  {
    // XXX Unlink from reflector here.
}

@end

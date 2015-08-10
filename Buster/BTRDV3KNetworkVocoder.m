//
//  BTRDV3KNetworkVocoder.m
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


#import "BTRDV3KNetworkVocoder.h"
#import "BTRDV3KVocoderSubclass.h"
#import "BTRDataEngine.h"
#import "BTRNetworkVocoderViewController.h"

#import <arpa/inet.h>
#import <sys/ioctl.h>

@interface BTRDV3KNetworkVocoder () {
    BTRNetworkVocoderViewController *_configurationViewController;
}

@end

@implementation BTRDV3KNetworkVocoder

+(void) load {
    [[BTRDataEngine sharedInstance] registerVocoderDriver:self];
}

- (id) init {
    self = [super init];
    if(self) {
        self.address = @"";
        self.port = 2460;
    }
    return self;
}

+(NSString *) name {
    return @"Network DV3000";
}

-(NSViewController *)configurationViewController {
    if(!_configurationViewController) {
        _configurationViewController = [[BTRNetworkVocoderViewController alloc] initWithNibName:@"BTRNetworkVocoderView" bundle:nil];
        _configurationViewController.driver = self;
    }
    return _configurationViewController;
}


- (BOOL) openPort {
    if([self.address isEqualToString:@""] || self.port == 0)
        return NO;
    
    self.descriptor = socket(PF_INET, SOCK_DGRAM, 0);
    if(self.descriptor == -1) {
        NSLog(@"Error opening socket: %s\n", strerror(errno));
        return NO;
    }
    
    int one = 1;
    if(setsockopt(self.descriptor, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one))) {
        NSLog(@"Couldn't set socket to SO_REUSEADDR: %s\n", strerror(errno));
        return NO;
    }
    
    /* NSMutableData *addrStructData = [[NSMutableData alloc] initWithLength:sizeof(struct sockaddr_in)];
    
    struct sockaddr_in *addrStruct = [addrStructData mutableBytes];
    addrStruct->sin_len = sizeof(struct sockaddr_in);
    addrStruct->sin_family = AF_INET;
    addrStruct->sin_port = htons(self.gatewayPort);
    addrStruct->sin_addr.s_addr = inet_addr([self.gatewayAddr cStringUsingEncoding:NSUTF8StringEncoding]);
    
    return [NSData dataWithData:addrStructData]; */

    
    struct sockaddr_in address = {
        .sin_len = sizeof(struct sockaddr_in),
        .sin_family = AF_INET,
        .sin_port = htons(self.port),
        .sin_addr.s_addr = inet_addr([self.address cStringUsingEncoding:NSUTF8StringEncoding])
    };
    
    if(connect(self.descriptor, (const struct sockaddr *) &address, (socklen_t) sizeof(address))) {
        NSLog(@"Couldn't connect socket: %s\n", strerror(errno));
        return NO;
    }
    
    return YES;
}

- (BOOL) setNonblocking {
    if(fcntl(self.descriptor, F_SETFL, O_NONBLOCK) == -1) {
        NSLog(@"Couldn't set socket to nonblocking: %s\n", strerror(errno));
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

- (BOOL) readPacket:(struct dv3k_packet *)packet {
    size_t bytesRead;
    
    bytesRead = recv(self.descriptor, packet, sizeof(struct dv3k_packet), 0);
    if(bytesRead == -1) {
        NSLog(@"Couldn't read from DV3K: %s", strerror(errno));
        return NO;
    }
    
    if(packet->start_byte != DV3K_START_BYTE) {
        NSLog(@"No start byte in packet");
        return NO;
    }

    return YES;
}

- (BOOL) writePacket:(const struct dv3k_packet *)packet {
    size_t bytesWritten;
    
    bytesWritten = send(self.descriptor, packet, dv3k_packet_size(*packet), 0);
    if(bytesWritten == -1) {
        NSLog(@"Couldn't write packet to DV3K: %s", strerror(errno));
        return NO;
    }
    
    return YES;
}


@end

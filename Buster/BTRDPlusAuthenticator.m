//
//  BTRDplusAuthenticator.m
//
//  Copyright (c) 2015 - Annaliese C. McDermond (NH6Z)

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


#import "BTRDPlusAuthenticator.h"

#import <arpa/inet.h>
#import <sys/ioctl.h>

struct dplus_authentication_request {
    char length;
    char type[2];
    char padding1;
    char authCall[8];
    char magicCall1[8];
    char blank1[8];
    char magicCall2[4];
    char magicCall2Suffix;
    char blank2[7];
    char magicCall3[7];
    char blank3[9];
} __attribute__((packed));


struct reflector_record {
    char address[16];
    char name[8];
    short flags;
} __attribute__((packed));

struct dplus_auth_response {
    struct {
        char type;
        char padding[5];
    } header;
    struct reflector_record records[];
} __attribute__((packed));

static const struct dplus_authentication_request requestTemplate = {
    .length = 0x38,
    .type = { 0xC0 , 0x01 },
    .padding1 = 0x00,
    .authCall = "        ",
    .magicCall1 = "DV019999",
    .blank1 = "        ",
    .magicCall2 = "W7IB",
    .magicCall2Suffix = '2',
    .blank2 = "       ",
    .magicCall3 = "DHS0257",
    .blank3 = "         "
};

static const unsigned long long NSEC_PER_HOUR = 3600ull * NSEC_PER_SEC;

@interface BTRDPlusAuthenticator () {
    dispatch_source_t authTimerSource;
}

@property (nonatomic, readwrite) NSDictionary *reflectorList;
@property (nonatomic, getter=isAuthenticated, readwrite) BOOL authenticated;
@property (nonatomic, readonly) char suffix;

- (void)startAuthTimer;
- (void)authenticate;

@end

@implementation BTRDPlusAuthenticator

- (id) init {
    self = [super init];
    if(self) {
        _reflectorList = nil;
        _authCall = @"";
        _suffix = '2';
        _authenticated = NO;
        
        BTRDPlusAuthenticator __weak *weakSelf = self;
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidWakeNotification object:NULL queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
            NSLog(@"Waking from sleep, reauthenticating");
            [weakSelf authenticate];
        }];
        [self bind:@"authCall" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.myCall" options:nil];
    }
    return self;
}

- (void) dealloc {
    dispatch_source_cancel(authTimerSource);
}

- (void) setAuthCall:(NSString *)authCall {
    if([authCall isEqualToString:_authCall])
        return;
    
    _authCall = [authCall copy];
    
    if(authTimerSource)
        dispatch_source_cancel(authTimerSource);
    
    [self startAuthTimer];
}

- (void) startAuthTimer {
    BTRDPlusAuthenticator __weak *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [weakSelf authenticate];
    });

    authTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_timer(authTimerSource, dispatch_walltime(NULL, 6ull * NSEC_PER_HOUR), 6ull * NSEC_PER_HOUR, 60ull * NSEC_PER_SEC);
    dispatch_source_set_event_handler(authTimerSource, ^{
        // XXX Do something with authentication failure here.  NSNotification?
        [weakSelf authenticate];
    });
    dispatch_resume(authTimerSource);
}

-(void) authenticate {
    CFStreamError error;
    Boolean resolved;
    CFHostRef authHost;

    self.authenticated = NO;
    
    NSLog(@"Performing DPlus authentication");
    
    if(!self.authCall)
        return;
    
    int authSocket = socket(PF_INET, SOCK_STREAM, 0);
    if(authSocket == -1) {
        NSLog(@"Couldn't create socket: %s", strerror(errno));
        return;
    }
    
    if ((authHost = CFHostCreateWithName(kCFAllocatorDefault, (CFStringRef) @"auth.dstargateway.org")) == NULL) {
        NSLog(@"Could not create host object");
        return;
    }
    if(CFHostStartInfoResolution(authHost, kCFHostAddresses, &error) == FALSE) {
        NSLog(@"Error resolving auth.dstargateway.org");
        return;
    }
    
    NSArray *addresses = (__bridge NSArray *) (CFHostGetAddressing(authHost, &resolved));
    if(!resolved) {
        NSLog(@"Cannot lookup auth.dstargateway.org");
        return;
    }
    
    bool connected = NO;
    for(NSData *addressData in addresses) {
        struct sockaddr_in *dNSAddr = (struct sockaddr_in *)[addressData bytes];
        char *addressString = inet_ntoa(dNSAddr->sin_addr);

        NSLog(@"Trying to connect to D-Plus authentication server at %s", addressString);
        struct sockaddr_in addr = {
            .sin_len = sizeof(struct sockaddr_in),
            .sin_family = AF_INET,
            .sin_port = htons(20001),
            .sin_addr.s_addr = dNSAddr->sin_addr.s_addr
        };
        
        if(connect(authSocket, (const struct sockaddr *) &addr, (socklen_t) sizeof(addr)) == -1) {
            NSLog(@"Couldn't connect to %s: %s\n", addressString, strerror(errno));
            close(authSocket);
            
            authSocket = socket(PF_INET, SOCK_STREAM, 0);
            if(authSocket == -1) {
                NSLog(@"Couldn't create socket: %s", strerror(errno));
                return;
            }
        } else {
            NSLog(@"Connected to D-Plus authentication server at %s", addressString);
            connected = YES;
            break;
        }
    }
    
    CFRelease(authHost);
    
    if(!connected) {
        NSLog(@"Couldn't connect to any D-Plus authentication servers");
        return;
    }
    
    struct dplus_authentication_request request;
    memcpy(&request, &requestTemplate, sizeof(requestTemplate));
    strncpy(request.authCall, [[self.authCall stringByPaddingToLength:8 withString:@" " startingAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding], sizeof(request.authCall));
    request.magicCall2Suffix = self.suffix;
    
    ssize_t bytesWritten = send(authSocket, &request, sizeof(request), 0);
    if(bytesWritten == -1) {
        NSLog(@"Couldn't write data: %s", strerror(errno));
        close(authSocket);
        return;
    }
    
    if(bytesWritten != sizeof(request)) {
        NSLog(@"Short write");
        close(authSocket);
        return;
    }
    
    unsigned short length = 0;
    ssize_t bytesRead = 0;
    NSMutableDictionary *newReflectorList = [NSMutableDictionary dictionaryWithCapacity:10];
    
    while((bytesRead = recv(authSocket, &length, sizeof(length), 0)) != 0) {
        if(bytesRead == -1) {
            NSLog(@"Couldn't read data: %s", strerror(errno));
            close(authSocket);
            return;
        }

        if(bytesRead != sizeof(length)) {
            NSLog(@"Short read, expected %ld, got %ld", sizeof(length), bytesRead);
            close(authSocket);
            return;
        }
        
        //  We need to remove two bytes for the length we already read.
        length = (length & 0x0FFF) - 2;
        
        char *buffer = calloc(1, length);
        
        ssize_t bytesLeft = length;
        while(bytesLeft > 0) {
            bytesRead = recv(authSocket, buffer + (length - bytesLeft), bytesLeft, 0);
            if(bytesRead == -1) {
                NSLog(@"Couldn't read rest of packet: %s", strerror(errno));
                free(buffer);
                close(authSocket);
                return;
            }
            bytesLeft -= bytesRead;
        }
        
        struct dplus_auth_response *response = (struct dplus_auth_response *) buffer;
        unsigned long numRecords = (length - sizeof(response->header)) / sizeof(struct reflector_record);
        for(int i = 0; i < numRecords; ++i)
            if((strnlen(response->records[i].address, sizeof(response->records[i].address)) > 0) && (response->records[i].flags & 0x8000))
                newReflectorList[[[NSString stringWithCString:response->records[i].name encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]] = [NSString stringWithCString:response->records[i].address encoding:NSUTF8StringEncoding];
       
        free(buffer);
    }
    
    self.reflectorList = [NSDictionary dictionaryWithDictionary:newReflectorList];
    
    NSLog(@"Received %ld responses from authentication server", self.reflectorList.count);
    
    close(authSocket);
    
    if(self.reflectorList.count > 0)
        self.authenticated = YES;
}

@end

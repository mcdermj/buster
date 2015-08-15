//
//  BTRDPlusAuthenticator.m
//  Buster
//
//  Created by Jeremy McDermond on 8/14/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import <arpa/inet.h>
#import <sys/ioctl.h>

struct dplus_authentication_request {
    char length;
    char type[2];
    char padding1;
    char authCall[8];
    char magicCall1[8];
    char blank1[8];
    char magicCall2[5];
    char blank2[7];
    char magicCall3[7];
    char blank3[9];
} __attribute__((packed));

struct reflector_record {
    char address[16];
    char name[8];
    short flags;
} __attribute__((packed));

#import "BTRDPlusAuthenticator.h"

@implementation BTRDPlusAuthenticator

-(void) authenticate {
    NSHost *opendstarHost = [NSHost hostWithName:@"opendstar.org"];
    NSMutableArray *reflectorList = [[NSMutableArray alloc] init];

    int authSocket = socket(PF_INET, SOCK_STREAM, 0);
    if(authSocket == -1) {
        NSLog(@"Couldn't create socket: %s", strerror(errno));
        return;
    }
    
    struct sockaddr_in addr = {
        .sin_len = sizeof(struct sockaddr_in),
        .sin_family = AF_INET,
        .sin_port = htons(20001),
        .sin_addr.s_addr = inet_addr([opendstarHost.address cStringUsingEncoding:NSUTF8StringEncoding])
    };
    
    if(connect(authSocket, (const struct sockaddr *) &addr, (socklen_t) sizeof(addr))) {
        NSLog(@"Couldn't connect socket: %s\n", strerror(errno));
        return;
    }
    
    struct dplus_authentication_request request = {
        .length = 0x38,
        .type = { 0xC0 , 0x01 },
        .padding1 = 0x00,
        .authCall = "NH6Z    ",
        .magicCall1 = "DV019999",
        .blank1 = "        ",
        .magicCall2 = "W7IB2",
        .blank2 = "       ",
        .magicCall3 = "DHS0257",
        .blank3 = "         "
    };
    
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
    
    NSLog(@"Sent %ld bytes", bytesWritten);
    
    unsigned short length = 0;
    ssize_t bytesRead = 0;
    
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
        bytesRead = recv(authSocket, buffer, length, 0);
        if(bytesRead == -1) {
            NSLog(@"Couldn't read rest of packet: %s", strerror(errno));
            close(authSocket);
            return;
        }
        
        if(bytesRead != length) {
            NSLog(@"Short read, expected %d, got %ld", length, bytesRead);
            //close(authSocket);
            //return;
        }
        
        struct reflector_record *records = (struct reflector_record *) (buffer + 6);
        unsigned long numRecords = (bytesRead - 6) / sizeof(struct reflector_record);
        NSLog(@"Processing %ld records", numRecords);
        
        for(int i = 0; i < numRecords; ++i) {
            if((strnlen(records[i].address, sizeof(records[i].address)) > 0) && (records[i].flags & 0x8000))
                [reflectorList addObject:@{ @"address": [NSString stringWithCString:records[i].address encoding:NSUTF8StringEncoding],
                                            @"name": [NSString stringWithCString:records[i].name encoding:NSUTF8StringEncoding],
                                            @"flags": [NSNumber numberWithUnsignedShort:records[i].flags]
                                            }
                 ];
        }
        
        free(buffer);
    }
    
    for(NSDictionary *reflector in reflectorList)
        NSLog(@"Addr: %@, Name: %@, Flags: %@", reflector[@"address"], reflector[@"name"], reflector[@"flags"]);
}

@end

//
//  BTRSlowDataHandler.m
//
// Copyright (c) 2010-2015 - Jeremy C. McDermond (NH6Z)

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

@import CoreLocation;

#import "BTRSlowDataCoder.h"
#import "BTRAprsLocation.h"

const char syncBytes[] = { 0x55, 0x2D, 0x16 };
const char scrambler[] = { 0x70, 0x4F, 0x93, 0x70, 0x4F, 0x93 };
const char filler[] = { 0x66, 0x66, 0x66 };

const char SLOW_DATA_TYPE_MASK = 0xF0;
const char SLOW_DATA_SEQUENCE_MASK = 0x0F;
const char SLOW_DATA_TYPE_TEXT = 0x40;
const char SLOW_DATA_TYPE_GPS = 0x30;

NS_INLINE void SCRAMBLE(unsigned char *data) {
    for(int i = 0; i < 6; ++i)
        data[i] ^= scrambler[i];
}

@interface BTRSlowDataCoder () {
    unsigned char dataFrame[6];
    unsigned char messageFrames[8][3];
}

@property (nonatomic) NSMutableData *messageData;
@property (nonatomic) NSMutableData *gpsData;
@property (nonatomic, getter=isTop) BOOL top;
@property (nonatomic, readonly) CLLocationManager *locationManager;
@property (nonatomic) BTRAprsLocation *currentLocation;
@property (nonatomic) NSUInteger rxStreamId;
@end

@implementation BTRSlowDataCoder

-(id) init {
    self = [super init];
    if(self) {
        _top = YES;
        _rxStreamId = 0;
        _messageData = [NSMutableData dataWithLength:20];
        memset(_messageData.mutableBytes, ' ', 20);
        if([CLLocationManager locationServicesEnabled]) {
            NSLog(@"Initializing location services");
            _locationManager = [[CLLocationManager alloc] init];
            self.locationManager.delegate = self;
            self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
            self.locationManager.distanceFilter = 100;
            [self.locationManager startUpdatingLocation];
        } else {
            NSLog(@"Location services not enabled");
        }
    }
    return self;
}

-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    if(!self.currentLocation) {
        self.currentLocation = [[BTRAprsLocation alloc] init];
        
        //  XXX This should come from elsewhere
        self.currentLocation.callsign = [[NSUserDefaults standardUserDefaults] stringForKey:@"myCall"];
    }
    
    self.currentLocation.location = locations.lastObject;
    NSLog(@"New Location = %@", locations.lastObject);
    
    NSString *dprsPacket = self.currentLocation.dprsPacket;
    unsigned long numChunks = dprsPacket.length / 5;
    if(dprsPacket.length % 5)
        numChunks++;
    char *chunks = malloc(6 * numChunks);
    char *chunkPtr = chunks;
    
    for(int i = 0; i < numChunks; ++i, chunkPtr += 6) {
        unsigned long length = 0;
        if((i + 1) * 5 > dprsPacket.length)
            length = dprsPacket.length - (i * 5);
        else
            length = 5;
        
        *chunkPtr = (char) (SLOW_DATA_TYPE_GPS | (length & 0x0F));
        
        [dprsPacket getBytes:chunkPtr + 1 maxLength:5 usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(i * 5, length) remainingRange:NULL];
    }
    
}

-(void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    NSLog(@"Location services failed: %@", error);
}

-(void)setMessage:(NSString *)message {
    
    NSParameterAssert(message != nil);
    
    char txMessageBytes[20];
    memset(txMessageBytes, ' ', 20);
    memcpy(txMessageBytes, message.UTF8String, strnlen(message.UTF8String, 20));
    
    _message = [NSString stringWithUTF8String:txMessageBytes];
    
    for(int i = 0; i < 8; i = i + 2) {
        int firstIndex = (i * 5) / 2;
        messageFrames[i][0] = 0x40 | ((char) i / 2);
        
        memcpy(&messageFrames[i][1], &txMessageBytes[firstIndex], 5);
        SCRAMBLE(messageFrames[i]);
    }
 }

-(void)addData:(void *)data streamId:(NSUInteger)streamId {
    
    NSParameterAssert(data != NULL);
    NSParameterAssert(streamId > 0);
    
    if(self.rxStreamId != streamId) {
        self.rxStreamId = streamId;
        memset(self.messageData.mutableBytes, ' ', 20);
        self.gpsData = nil;
    }
    
    if(!memcmp(data, syncBytes, 3)) {
        self.top = YES;
        return;
    }
    
    if(self.isTop) {
        memcpy(dataFrame, data, 3);
        self.top = NO;
        return;
    }
    
    memcpy(dataFrame + 3, data, 3);
    SCRAMBLE((unsigned char *) dataFrame);
    
    switch(dataFrame[0] & SLOW_DATA_TYPE_MASK) {
        case SLOW_DATA_TYPE_TEXT:
            [self parseMessageData:dataFrame forStreamId:streamId];
            break;
        case SLOW_DATA_TYPE_GPS:
            [self parseGPSData:dataFrame forStreamId:streamId];
            break;
        default:
            //NSLog(@"Unknown Frame Type: 0x%02X", dataFrame[0] & SLOW_DATA_TYPE_MASK);
            break;
    }
    
    self.top = YES;
}

-(void)parseMessageData:(unsigned char *)data forStreamId:(NSUInteger)streamId {
    unsigned char sequence = *data & SLOW_DATA_SEQUENCE_MASK;
    if(sequence > 3) {
        NSLog(@"Bad sequence 0x%02X", sequence);
        self.top = YES;
        return;
    }
    
    [self.messageData replaceBytesInRange:NSMakeRange(sequence * 5, 5) withBytes:data + 1];
    
    if(sequence == 3) {
        //  Send the notification and reset messageData
        NSString *rxMessage = [[NSString alloc] initWithData:self.messageData encoding:NSUTF8StringEncoding];
        if(rxMessage)
            [self.delegate slowDataReceived:rxMessage forStreamId:[NSNumber numberWithUnsignedInteger:streamId]];
        
        memset(self.messageData.mutableBytes, ' ', 20);
    }
}

-(void)parseGPSData:(unsigned char *)data forStreamId:(NSUInteger)streamId {
    unsigned char length = *data & SLOW_DATA_SEQUENCE_MASK;
    if(length > 5) {
        NSLog(@"Invalid GPS frame length %d", length);
        return;
    }
    
    //  Discard a frame with only a newline
    if(length == 1 && data[1] == '\n')
        return;
    
    if(!self.gpsData)
        self.gpsData = [[NSMutableData alloc] init];
    
    [self.gpsData appendBytes:data + 1 length:length];
    
    // No valid sentence can be over 115 bytes long and
    // NMEA data can't be over 80 bytes long without the \r\n
    if(self.gpsData.length > 115 ||
       (memcmp(self.gpsData.bytes, "$GP", 3) && self.gpsData.length > 82)) {
        NSLog(@"Run on GPS data");
        self.gpsData = nil;
        return;
    }
    
    if(length < 5 || data[5] == '\r') {
        //  This is the last frame for this transmission
        NSString *gpsString = [[NSString alloc] initWithData:self.gpsData encoding:NSASCIIStringEncoding];
        if(gpsString == nil) {
            NSLog(@"GPS data cannot be parsed as ASCII");
            self.gpsData = nil;
            return;
        }
        
        if(gpsString.length < 9) {
            NSLog(@"GPS String too short: %@", gpsString);
            self.gpsData = nil;
            return;
        }
        
        BTRAprsLocation *location;
        
        NSString *gpsType = [gpsString substringToIndex:4];
        if([gpsType isEqualToString:@"$CRC"] || [gpsType isEqualToString:@"$$CR"]){
                location = [[BTRAprsLocation alloc] initWithAprsPacket:gpsString];
        } else if([gpsType isEqualToString:@"$GPG"]) {
            //  Handle GPGGA
            NSLog(@"GPGGA");
            location = [[BTRAprsLocation alloc] initWithNmeaSentence:gpsString];
        } else if([gpsType isEqualToString:@"$GPR"]) {
            //  Handle GPRMC
            NSLog(@"GPRMC");
            location = [[BTRAprsLocation alloc] initWithNmeaSentence:gpsString];
        } else if(gpsString.length == 31 && [[gpsString substringWithRange:NSMakeRange(8, 1)] isEqualToString:@","]){
            //  This is probably an ID line
            NSLog(@"ID Line");
        } else {
            NSLog(@"Length = %ld, string = %@", gpsString.length, gpsString);
        }
        
        if(location)
            [self.delegate locationReceived:location forStreamId:[NSNumber numberWithUnsignedInteger:streamId]];

        NSLog(@"Location = %@", location.location);
        self.gpsData = nil;
    }
}

-(const void *)getDataForSequence:(NSUInteger)sequence {
    if(sequence == 0)
        return syncBytes;
    
    if(self.currentLocation == nil) {
        if(sequence < 9)
            return messageFrames[sequence - 1];
    } else {
        
    }
    
    return filler;
}

@end

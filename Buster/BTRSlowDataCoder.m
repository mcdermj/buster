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

NS_INLINE uint16 gps_calc_sum(unsigned char *data, size_t length) {
    uint16 crc = 0xFFFF;
    
    for(int j = 0; j < length; ++j) {
        unsigned int ch = data[j] & 0xFF;
        for(int i = 0; i < 8; ++i) {
            BOOL xorflag = (((crc ^ ch) & 0x01) == 0x01);
            crc >>= 1;
            if(xorflag)
                crc ^= 0x8408;
            ch >>= 1;
        }
    }
    return (~crc) & 0xFFFF;
}

@interface CLLocation (BTRDstarUtils)

+(CLLocation *)locationWithAPRSString:(NSString *)aprsString;
+(CLLocation *)locationWithNMEASentence:(NSString *)nmeaSentence;
+(CLLocationDegrees)decimalCoordinateFromString:(NSString *)coordinate;
@end

@implementation CLLocation (BTRDstarUtils)

+(CLLocationDegrees)decimalCoordinateFromString:(NSString *)coordinate {
    NSString *direction = [coordinate substringFromIndex:coordinate.length - 1];
    double result = 0.0;
    
    if([direction isEqualToString:@"N"] || [direction isEqualToString:@"S"]) {
        result = [coordinate substringWithRange:NSMakeRange(0, 2)].floatValue + ([coordinate substringWithRange:NSMakeRange(2, coordinate.length - 2)].floatValue / 60.0);
        if([direction isEqualToString:@"S"])
            result = -result;
    } else if([direction isEqualToString:@"E"] || [direction isEqualToString:@"W"]) {
        result = [coordinate substringWithRange:NSMakeRange(0, 3)].floatValue + ([coordinate substringWithRange:NSMakeRange(3, coordinate.length - 3)].floatValue / 60.0);
        if([direction isEqualToString:@"W"])
            result = -result;
    }

    return result;
}

+(CLLocation *)locationWithNMEASentence:(NSString *)nmeaSentence {
    NSArray<NSString *> *nmeaComponents = [nmeaSentence componentsSeparatedByString:@","];
    CLLocation *location = nil;
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    formatter.dateFormat = @"HHmmss";
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    
    if([nmeaComponents[0] isEqualToString:@"$GPGGA"]) {
        if([nmeaComponents[4] isEqualToString:@"0"]) {
            NSLog(@"Invalid NMEA fix");
            return nil;
        }
        CLLocationCoordinate2D coordinate = {
            .latitude = [CLLocation decimalCoordinateFromString:[nmeaComponents[2] stringByAppendingString:nmeaComponents[3]]],
            .longitude = [CLLocation decimalCoordinateFromString:[nmeaComponents[4] stringByAppendingString:nmeaComponents[5]]]
        };
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSDateComponents *timestampComponents = [[NSCalendar currentCalendar] components:(NSCalendarUnitYear | NSCalendarUnitMonth |  NSCalendarUnitDay) fromDate:[NSDate date]];
        NSDateComponents *timeComponents = [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute |  NSCalendarUnitSecond) fromDate:[formatter dateFromString:nmeaComponents[1]]];
#pragma clang diagnostic pop
        timestampComponents.hour = timeComponents.hour;
        timestampComponents.minute = timeComponents.minute;
        timestampComponents.second = timeComponents.second;
        
        location = [[CLLocation alloc] initWithCoordinate:coordinate
                                                 altitude:nmeaComponents[7].doubleValue
                                       horizontalAccuracy:nmeaComponents[6].doubleValue
                                         verticalAccuracy:100.0
                                                   course:0.0
                                                    speed:0.0
                                                timestamp:[[NSCalendar currentCalendar] dateFromComponents:timestampComponents]];
    } else if([nmeaComponents[0] isEqualToString:@"$GPRMC"]) {
        if([nmeaComponents[2] isEqualToString:@"V"]) {
            NSLog(@"Void NMEA position");
            return nil;
        }
        
        CLLocationCoordinate2D coordinate = {
            .latitude = [CLLocation decimalCoordinateFromString:[nmeaComponents[3] stringByAppendingString:nmeaComponents[4]]],
            .longitude = [CLLocation decimalCoordinateFromString:[nmeaComponents[5] stringByAppendingString:nmeaComponents[6]]]
        };
        
        NSDateComponents *timestampComponents = [[NSDateComponents alloc] init];
        timestampComponents.day = [nmeaComponents[9] substringWithRange:NSMakeRange(0, 2)].integerValue;
        timestampComponents.month = [nmeaComponents[9] substringWithRange:NSMakeRange(2, 2)].integerValue;
        timestampComponents.year = [nmeaComponents[9] substringWithRange:NSMakeRange(4, 2)].integerValue;
        timestampComponents.hour = [nmeaComponents[1] substringWithRange:NSMakeRange(0, 2)].integerValue;
        timestampComponents.minute = [nmeaComponents[1] substringWithRange:NSMakeRange(2, 2)].integerValue;
        timestampComponents.second = [nmeaComponents[1] substringWithRange:NSMakeRange(4, 2)].integerValue;
        // NSDate *timeStamp = [[NSCalendar currentCalendar] dateFromComponents:timestampComponents];
        
        location = [[CLLocation alloc] initWithCoordinate:coordinate
                                                 altitude:0.0
                                       horizontalAccuracy:100.0
                                         verticalAccuracy:100.0
                                                   course:nmeaComponents[8].doubleValue
                                                    speed:nmeaComponents[7].doubleValue * 0.514444 // convert from knots
                                                timestamp:[[NSCalendar currentCalendar] dateFromComponents:timestampComponents]];
    } else {
        NSLog(@"Invalid NMEA sentence");
    }
    
    return location;

}
+(CLLocation *)locationWithAPRSString:(NSString *)aprsString {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    NSError *error;
    
    NSRegularExpression *parser = [NSRegularExpression regularExpressionWithPattern:@"^\\$?\\$CRC([0-9A-F]{4}),[0-9A-Z]{4,8}>[0-9A-Z]{4,8},DSTAR\\*:[!\\/]{1}(?:[0-9]{6}[hz\\/]{1})?(\\d{4}\\.\\d{2}[NS]{1})(.{1})(\\d{5}\\.\\d{2}[EW]{1})(.{1})(\\d{3}\\/\\d{3})?(.*)$" options:0 error:&error];
    
    NSUInteger numberOfMatches = [parser numberOfMatchesInString:aprsString options:0 range:NSMakeRange(0, [aprsString length])];
    if(numberOfMatches != 1) {
        NSLog(@"Invalid GPS string: %@", aprsString);
        return nil;
    }
    
    NSTextCheckingResult *match = [parser firstMatchInString:aprsString options:0 range:NSMakeRange(0, [aprsString length])];
    
    unsigned int crc;
    NSScanner *crcScanner = [NSScanner scannerWithString:[aprsString substringWithRange:[match rangeAtIndex:1]]];
    if(![crcScanner scanHexInt:&crc]) {
        NSLog(@"Couldn't parse checksum");
        return nil;
    }
    
    size_t maxLength = [aprsString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    unsigned char *bytes = malloc(maxLength);
    [aprsString getBytes:bytes maxLength:maxLength usedLength:NULL encoding:NSUTF8StringEncoding options:0 range:NSMakeRange(0, [aprsString length]) remainingRange:NULL];
    unsigned int calcCrc = gps_calc_sum(bytes + 9, maxLength - 9);
    if(crc != calcCrc) {
        NSLog(@"CRC mismatch on GPS packet.  Received 0x%04X, calculated 0x%04X", crc, calcCrc);
        return nil;
    }
    
    //  XXX We can pack this with more data.
    //  XXX CLLocation can take course/speed information as well.  This can be optionally parsed from the string.
    //  XXX CLLocation can also take a time.  This can be parsed optionally from the time stuff.

    return [[CLLocation alloc] initWithLatitude:[CLLocation decimalCoordinateFromString:[aprsString substringWithRange:[match rangeAtIndex:2]]]
                                      longitude:[CLLocation decimalCoordinateFromString:[aprsString substringWithRange:[match rangeAtIndex:4]]]];
#pragma clang diagnostic pop
}

@end

@interface BTRSlowDataCoder () {
    unsigned char dataFrame[6];
    unsigned char messageFrames[8][3];
}

@property (nonatomic) NSMutableData *messageData;
@property (nonatomic) NSMutableData *gpsData;
@property (nonatomic, getter=isTop) BOOL top;
@property (nonatomic, readonly) NSRegularExpression *gpsExpression;
@property (nonatomic, readonly) CLGeocoder *geocoder;
@end

@implementation BTRSlowDataCoder

-(id) init {
    self = [super init];
    if(self) {
        _top = YES;
        _messageData = [NSMutableData dataWithLength:20];
        memset(_messageData.mutableBytes, ' ', 20);
        _geocoder = [[CLGeocoder alloc] init];
        
        NSError *error = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        _gpsExpression = [NSRegularExpression regularExpressionWithPattern:@"^\\$CRC([0-9A-F]{4}),[0-9A-Z]{4,8}>[0-9A-Z]{4,8},DSTAR\\*:[!\\/]{1}(?:[0-9]{6}[hz\\/]{1})?(\\d{4}\\.\\d{2}[NS]{1})(.{1})(\\d{5}\\.\\d{2}[EW]{1})(.{1})(\\d{3}\\/\\d{3})?(.*)$" options:0 error:&error];
        
        NSArray <NSString *> *testStrings = @[
                                              @"$CRC2587,WA8CLT>API510,DSTAR*:!4000.94N/08304.82W>/\r",
                                              @"$CRCBA51,KC8YQL>API282,DSTAR*:/204914h4107.74N/08416.01WO320/000/2820 @ HOME QTH\r",
                                              @"$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47\r",
                                              @"$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A\r\n"
                                              ];
        for(NSString *testString in testStrings) {
            CLLocation *testLocation = [CLLocation locationWithNMEASentence:testString];
            if(testLocation)
                NSLog(@"Location = %@", testLocation);
            testLocation = [CLLocation locationWithAPRSString:testString];
            if(testLocation)
                NSLog(@"Location = %@", testLocation);
        }
        //  Test the regexp with a couple of strings
        /* NSString *testString = @"$CRC2587,WA8CLT>API510,DSTAR*:!4000.94N/08304.82W>/\r";
        [self parseGPSString:testString];
        testString = @"$CRCBA51,KC8YQL>API282,DSTAR*:/204914h4107.74N/08416.01WO320/000/2820 @ HOME QTH\r";
        [self parseGPSString:testString];
        testString = @"$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47\r\n";
        CLLocation *testLocation = [CLLocation locationWithNMEASentence:testString];
        NSLog(@"Location = %@", testLocation);
        testString = @"$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A\r\n";
        testLocation = [CLLocation locationWithNMEASentence:testString];
        NSLog(@"Location = %@", testLocation); */

#pragma clang diagnostic pop
    }
    return self;
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
    
    // NSLog(@"Parsing GPS frame");
    
    if(!self.gpsData)
        self.gpsData = [[NSMutableData alloc] init];
    
    [self.gpsData appendBytes:data + 1 length:length];
    if(length < 5) {
        //  This is the last frame for this transmission
        NSString *gpsString = [[NSString alloc] initWithData:self.gpsData encoding:NSUTF8StringEncoding];
        if(gpsString == nil) {
            NSLog(@"GPS data cannot be parsed as UTF-8");
            self.gpsData = nil;
            return;
        }
        
        if(gpsString.length < 4) {
            NSLog(@"GPS String too short");
            return;
        }
        
        CLLocation *location;
        
        NSString *gpsType = [gpsString substringToIndex:4];
        if([gpsType isEqualToString:@"$CRC"]){
            location = [CLLocation locationWithAPRSString:gpsString];
            [self parseGPSString:gpsString];
        } else if([gpsType isEqualToString:@"$GPG"]) {
            //  Handle GPGGA
            NSLog(@"GPGGA");
            location = [CLLocation locationWithNMEASentence:gpsString];
        } else if([gpsType isEqualToString:@"$GPR"]) {
            //  Handle GPRMC
            NSLog(@"GPRMC");
            location = [CLLocation locationWithNMEASentence:gpsString];
        } else if(gpsString.length == 31 && [[gpsString substringWithRange:NSMakeRange(8, 1)] isEqualToString:@","]){
            //  This is probably an ID line
            NSLog(@"ID Line");
        } else {
            NSLog(@"Length = %ld, string = %@", gpsString.length, gpsString);
        }
        
        NSLog(@"Location = %@", location);
        self.gpsData = nil;
    }
}

-(NSDictionary *)parseGPSString:(NSString *)gpsString {
    NSDictionary *gpsInfo = @{
                              @"location" : [CLLocation locationWithAPRSString:gpsString],
//                              @"comment" : [gpsString substringWithRange:[match rangeAtIndex:match.numberOfRanges - 1]]
                              };
    
    NSLog(@"GPS Info = %@", gpsInfo);
    
    [self.geocoder reverseGeocodeLocation:gpsInfo[@"location"] completionHandler:^(NSArray *placemarks, NSError *error) {
        if(!placemarks)
            NSLog(@"placemarks are nil");
        if(error)
            NSLog(@"Error returned from geocoder: %@", error);
        if(placemarks.count == 0)
            NSLog(@"No placemarks returned");
        
        for(CLPlacemark *placemark in placemarks) {
            NSLog(@"Location is in %@, %@, %@", placemark.locality, placemark.administrativeArea, placemark.country);
        }
    }];
    
    return gpsInfo;
}

-(const void *)getDataForSequence:(NSUInteger)sequence {
    if(sequence == 0) {
        return syncBytes;
    } else if(sequence < 9) {
        return messageFrames[sequence - 1];
    } else {
        return filler;
    }
}

@end

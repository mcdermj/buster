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

NS_INLINE unsigned char nmea_calc_sum(unsigned char *data, size_t length) {
    unsigned char sum = 0x00;
    
    for(int i = 0; i < length; ++i)
        sum ^= data[i];
    
    return sum;
}

@interface BTRSlowDataCoder () {
    unsigned char dataFrame[6];
    unsigned char messageFrames[8][3];
}

@property (nonatomic) NSMutableData *messageData;
@property (nonatomic) NSMutableData *gpsData;
@property (nonatomic, getter=isTop) BOOL top;
@end

@implementation BTRSlowDataCoder

-(id) init {
    self = [super init];
    if(self) {
        _top = YES;
        _messageData = [NSMutableData dataWithLength:20];
        memset(_messageData.mutableBytes, ' ', 20);
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
        NSString *gpsString = [[NSString alloc] initWithData:self.gpsData encoding:NSASCIIStringEncoding];
        if(gpsString == nil) {
            NSLog(@"GPS data cannot be parsed as ASCII");
            self.gpsData = nil;
            return;
        }
        
        if(gpsString.length < 4) {
            NSLog(@"GPS String too short: %@", gpsString);
            self.gpsData = nil;
            return;
        }
        
        CLLocation *location;
        
        NSString *gpsType = [gpsString substringToIndex:4];
        if([gpsType isEqualToString:@"$CRC"] || [gpsType isEqualToString:@"$$CR"]){
            location = [self locationFromAprsPacket:gpsString];
        } else if([gpsType isEqualToString:@"$GPG"]) {
            //  Handle GPGGA
            NSLog(@"GPGGA");
            location = [self locationFromNmeaSentence:gpsString];
        } else if([gpsType isEqualToString:@"$GPR"]) {
            //  Handle GPRMC
            NSLog(@"GPRMC");
            location = [self locationFromNmeaSentence:gpsString];
        } else if(gpsString.length == 31 && [[gpsString substringWithRange:NSMakeRange(8, 1)] isEqualToString:@","]){
            //  This is probably an ID line
            NSLog(@"ID Line");
        } else {
            NSLog(@"Length = %ld, string = %@", gpsString.length, gpsString);
        }
        
        if(location)
            [self.delegate locationReceived:location forStreamId:[NSNumber numberWithUnsignedInteger:streamId]];

        NSLog(@"Location = %@", location);
        self.gpsData = nil;
    }
}

-(NSDate *)dateFromARPSTimestamp:(NSString *)timestamp {
    NSError *error = nil;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    NSRegularExpression *parser = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{2})(\\d{2})(\\d{2})(z|h|\\/)$" options:0 error:&error];
    if([parser numberOfMatchesInString:timestamp options:0 range:NSMakeRange(0, timestamp.length)] != 1) {
        return [NSDate distantPast];
    }
    
    NSTextCheckingResult *match = [parser firstMatchInString:timestamp options:0 range:NSMakeRange(0, timestamp.length)];
#pragma clang diagnostic pop
    NSString *stampType = [timestamp substringWithRange:[match rangeAtIndex:4]];
    
    NSCalendar *utcCalendar = [NSCalendar currentCalendar];
    utcCalendar.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    
    if([stampType isEqualToString:@"h"]) {
        NSUInteger hour = [timestamp substringWithRange:[match rangeAtIndex:1]].integerValue;
        NSUInteger minute = [timestamp substringWithRange:[match rangeAtIndex:2]].integerValue;
        NSUInteger second = [timestamp substringWithRange:[match rangeAtIndex:3]].integerValue;
        
        if(hour > 23 || minute > 59 || second > 59)
            return [NSDate distantPast];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSDateComponents *timestampComponents = [utcCalendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:[NSDate date]];
#pragma clang diagnostic pop
        timestampComponents.hour = hour;
        timestampComponents.minute = minute;
        timestampComponents.second = second;
        NSDate *timestampDate = [utcCalendar dateFromComponents:timestampComponents];
        
        if([[NSDate dateWithTimeIntervalSinceNow: 3900.0] compare:timestampDate] == NSOrderedAscending) {
            timestampComponents.day -= 1;
        } else if([[NSDate dateWithTimeIntervalSinceNow: -82500.0] compare:timestampDate] == NSOrderedDescending) {
            timestampComponents.day += 1;
        }
        
        return [utcCalendar dateFromComponents:timestampComponents];
    } else {
        NSAssert([stampType isEqualToString:@"z"] || [stampType isEqualToString:@"/"], @"Stamp Type not equal to either z, h, or /");
        NSUInteger day = [timestamp substringWithRange:[match rangeAtIndex:1]].integerValue;
        NSUInteger hour = [timestamp substringWithRange:[match rangeAtIndex:2]].integerValue;
        NSUInteger minute = [timestamp substringWithRange:[match rangeAtIndex:3]].integerValue;
        
        if(day < 1 || day > 31 || hour > 23 || minute > 59)
            return [NSDate distantPast];
        
        NSCalendar *timestampCalendar;
        if([stampType isEqualToString:@"z"])
            timestampCalendar = utcCalendar;
        else
            timestampCalendar = [NSCalendar currentCalendar];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSDateComponents *timestampComponents = [timestampCalendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:[NSDate date]];
#pragma clang diagnostic pop
        timestampComponents.day = day;
        timestampComponents.hour = hour;
        timestampComponents.minute = minute;
        
        NSDate *currentTimestamp = [timestampCalendar dateFromComponents:timestampComponents];
        
        NSDateComponents *diffComponents = [[NSDateComponents alloc] init];
        diffComponents.month = 1;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSDate *futureTimestamp = [timestampCalendar dateByAddingComponents:diffComponents toDate:currentTimestamp options:0];
        diffComponents.month = -1;
        NSDate *pastTimestamp = [timestampCalendar dateByAddingComponents:diffComponents toDate:currentTimestamp options:0];
#pragma clang diagnostic pop
        
        if(futureTimestamp && futureTimestamp.timeIntervalSinceNow < 43400.0)
            return futureTimestamp;
        else if(currentTimestamp && currentTimestamp.timeIntervalSinceNow < 43400.0)
            return currentTimestamp;
        else if (pastTimestamp)
            return pastTimestamp;
    }

    return [NSDate distantPast];
}

-(CLLocationDegrees) coordinatesFromNmeaString:(NSString *)nmeaString withSign:(NSString *)sign {
    NSError *error;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    NSRegularExpression *parser = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d{1,3})([0-5][0-9])\\.(\\d+)\\s*$" options:0 error:&error];
    if([parser numberOfMatchesInString:nmeaString options:0 range:NSMakeRange(0, nmeaString.length)] != 1)
        return 0.0;
    
    NSTextCheckingResult *match = [parser firstMatchInString:nmeaString options:0 range:NSMakeRange(0, nmeaString.length)];
#pragma clang diagnostic pop
    CLLocationDegrees degrees = [nmeaString substringWithRange:[match rangeAtIndex:1]].doubleValue + [nmeaString substringWithRange:NSUnionRange([match rangeAtIndex:2], [match rangeAtIndex:3])].doubleValue / 60.0;
    
    sign = [sign.uppercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if([sign isEqualToString:@"E"] || [sign isEqualToString:@"W"]) {
        if(degrees > 179.9999999)
            return 0.0;
    } else if([sign isEqualToString:@"N"] || [sign isEqualToString:@"S"]) {
        if(degrees > 89.9999999)
            return 0.0;
    } else {
        return 0.0;
    }
    
    if([sign isEqualToString:@"S"] || [sign isEqualToString:@"W"])
        degrees = -degrees;
    
    return degrees;
}

-(CLLocation *) locationFromAprsPacket:(NSString *)aprsPacket {
    NSError *error = nil;
    
    // aprsPacket = [aprsPacket stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    //  XXX Need to work out the test packets with proper checksums
    NSRegularExpression *parser = [NSRegularExpression regularExpressionWithPattern:@"^\\${1,2}CRC([0-9A-Z]{4}),(.*\r)$" options:NSRegularExpressionCaseInsensitive error:&error];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    NSArray <NSTextCheckingResult *> *matches = [parser matchesInString:aprsPacket options:0 range:NSMakeRange(0, aprsPacket.length)];
#pragma clang diagnostic pop
    if(matches.count != 1)
        return nil;
    
    unsigned int crc;
    NSScanner *crcScanner = [NSScanner scannerWithString:[aprsPacket substringWithRange:[matches[0] rangeAtIndex:1]]];
    if(![crcScanner scanHexInt:&crc]) {
        NSLog(@"Couldn't parse checksum");
        return nil;
    }
    
    NSString *bareAprsPacket = [aprsPacket substringWithRange:[matches[0] rangeAtIndex:2]];
    size_t maxLength = [bareAprsPacket lengthOfBytesUsingEncoding:NSASCIIStringEncoding];
    unsigned char *bytes = malloc(maxLength);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    [bareAprsPacket getBytes:bytes maxLength:maxLength usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, bareAprsPacket.length) remainingRange:NULL];
#pragma clang diagnostic pop
    unsigned int calcCrc = gps_calc_sum(bytes, maxLength);
    
    if(crc != calcCrc) {
        NSLog(@"CRC mismatch on GPS packet \"%@\".  Received 0x%04X, calculated 0x%04X", bareAprsPacket, crc, calcCrc);
        return nil;
    }
    free(bytes);

    if(aprsPacket.length < 1)
        return nil;
    
    NSArray <NSString *> *components = [bareAprsPacket componentsSeparatedByString:@":"];
    if(components.count < 2)
        return nil;
    
    // NSString *header = components[0];
    NSString *body = [[components subarrayWithRange:NSMakeRange(1, components.count -1)] componentsJoinedByString:@""];
    //  XXX We should probably do something with the header and get source and destination callsigns here to be put in a dictionary.
    
    NSString *packetType = [body substringWithRange:NSMakeRange(0, 1)];
    if([packetType isEqualToString:@"!"] ||
       [packetType isEqualToString:@"="] ||
       [packetType isEqualToString:@"/"] ||
       [packetType isEqualToString:@"@"]) {
        //  Position Packet
        NSDate *timestamp = nil;
        //  If packetTyep == ! or /, messaging == yes, these shouldn't be received on DSTAR.
        
        if(body.length < 14)
            return nil;
        
        if([packetType isEqualToString:@"/"] ||
           [packetType isEqualToString:@"@"]) {
            timestamp = [self dateFromARPSTimestamp:[body substringWithRange:NSMakeRange(1, 7)]];
            if([timestamp isEqualToDate:[NSDate distantPast]])
                return nil;  // XXX Shouldn't error here, just give current date.
            body = [body substringFromIndex:7];
        }
        
        body = [body substringFromIndex:1];
        if([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[body characterAtIndex:1]]) {
            if(body.length < 19)
                return nil;
            
            //  Parse the APRS position meat
            CLLocation *position = [self locationFromAprsPositionPacket:body];
            if(timestamp)
                position = [[CLLocation alloc] initWithCoordinate:position.coordinate
                                                         altitude:position.altitude
                                               horizontalAccuracy:position.horizontalAccuracy
                                                 verticalAccuracy:position.verticalAccuracy
                                                           course:position.course
                                                            speed:position.speed
                                                        timestamp:timestamp];
            
            return position;
        }
        
        //  XXX We could have compressed packets here
        return nil;
    } else if([packetType isEqualToString:@";"]) {
        //  Object
        if(body.length < 31)
            return nil;

        return [[CLLocation alloc] initWithLatitude:0.0 longitude:0.0];
    } else if([packetType isEqualToString:@">"]) {
        //  Status Report
        
        return [[CLLocation alloc] initWithLatitude:0.0 longitude:0.0];
    }
    
    return nil;
}

-(CLLocation *)locationFromAprsPositionPacket:(NSString *)positionPacket {
    NSError *error;
    
    double lonDeg = 0;
    double latDeg = 0;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
NSRegularExpression *parser = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{2})([0-7 ][0-9 ]\\.[0-9 ]{2})([NnSs])(.)(\\d{3})([0-7 ][0-9 ]\\.[0-9 ]{2})([EeWw])([\\x21-\\x7b\\x7d])" options:0 error:&error];
    NSArray <NSTextCheckingResult *> *matches = [parser matchesInString:positionPacket options:0 range:NSMakeRange(0, positionPacket.length)];
#pragma clang diagnostic pop
    if(matches.count != 1)
        return nil;
    
    NSString *sInd = [[positionPacket substringWithRange:[matches[0] rangeAtIndex:3]] uppercaseString];
    NSString *wInd = [[positionPacket substringWithRange:[matches[0] rangeAtIndex:7]] uppercaseString];
    latDeg = [positionPacket substringWithRange:[matches[0] rangeAtIndex:1]].doubleValue;
    NSString *latMin = [positionPacket substringWithRange:[matches[0] rangeAtIndex:2]];
    lonDeg = [positionPacket substringWithRange:[matches[0] rangeAtIndex:5]].doubleValue;
    NSString *lonMin = [positionPacket substringWithRange:[matches[0] rangeAtIndex:6]];
    
    NSString *symbolTable = [positionPacket substringWithRange:[matches[0] rangeAtIndex:4]];
    //NSString *symbolCode = [positionPacket substringWithRange:[matches[0] rangeAtIndex:8]];
    
    if(![[NSCharacterSet characterSetWithCharactersInString:@"\\/ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"] characterIsMember:[symbolTable characterAtIndex:0]]) {
        //  Invalid symbol table
        return nil;
    }
    
    if(latDeg > 89.0 || lonDeg > 179.0)
        return nil;
    
    NSString *tmpLat = [latMin stringByReplacingOccurrencesOfString:@"." withString:@""];  //  I don't know why we're doing this
    NSInteger posAmbiguity = tmpLat.length - [tmpLat stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length;
    // NSLog(@"Ambiguity = %ld", posAmbiguity);
    
    CLLocationCoordinate2D coordinate = {
        .latitude = 0.0,
        .longitude = 0.0
    };
    
    switch(posAmbiguity) {
        case 0:
            if([lonMin componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].count > 1)
                return nil;
            coordinate.latitude = latDeg + (latMin.doubleValue / 60.0);
            coordinate.longitude = lonDeg + (lonMin.doubleValue / 60.0);
            break;
        case 1:
            latMin = [latMin substringWithRange:NSMakeRange(0, 4)];
            lonMin = [lonMin substringWithRange:NSMakeRange(0, 4)];
            if([lonMin componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].count > 1 ||
               [latMin componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].count > 1)
                return nil;
            
            coordinate.latitude = latDeg + ((latMin.doubleValue + 0.05) / 60.0);
            coordinate.longitude = lonDeg + ((lonMin.doubleValue + 0.05) / 60.0);
            break;
        case 2:
            latMin = [latMin substringWithRange:NSMakeRange(0, 2)];
            lonMin = [lonMin substringWithRange:NSMakeRange(0, 2)];
            if([lonMin componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].count > 1 ||
               [latMin componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].count > 1)
                return nil;
            
            coordinate.latitude = latDeg + ((latMin.doubleValue + 0.5) / 60.0);
            coordinate.longitude = lonDeg + ((lonMin.doubleValue + 0.5) / 60.0);
            break;
        case 3:
            latMin = [[latMin substringWithRange:NSMakeRange(0, 1)] stringByAppendingString:@"5"];
            lonMin = [[lonMin substringWithRange:NSMakeRange(0, 1)] stringByAppendingString:@"5"];
            if([lonMin componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].count > 1 ||
               [latMin componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].count > 1)
                return nil;
            
            coordinate.latitude = latDeg + (latMin.doubleValue / 60.0);
            coordinate.longitude = lonDeg + (lonMin.doubleValue / 60.0);
            break;
        case 4:
            coordinate.latitude = latDeg + 0.5;
            coordinate.longitude = lonDeg + 0.5;
            break;
        default:
            return nil;
    }
    
    if([sInd isEqualToString:@"S"])
        coordinate.latitude = -coordinate.latitude;
    if([wInd isEqualToString:@"W"])
        coordinate.longitude = -coordinate.longitude;
    
    posAmbiguity = 2 - posAmbiguity;
    CLLocationAccuracy resolution = 1.852 * (posAmbiguity <= -2 ? 600.0 : 1000.0) * pow(10, -posAmbiguity);
    
    //  Advance to process comment
    positionPacket = [positionPacket substringFromIndex:19];
    CLLocationDirection course = 0.0;
    CLLocationSpeed speed = 0.0;
    CLLocationDistance altitude = 0.0;
    CLLocationAccuracy verticalAccuracy = -1.0;
    NSRegularExpression *commentParser;
    if(positionPacket.length >= 7) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        commentParser = [NSRegularExpression regularExpressionWithPattern:@"^([0-9. ]{3})/([0-9. ]{3})" options:0 error:&error];
        matches = [commentParser matchesInString:positionPacket options:0 range:NSMakeRange(0, positionPacket.length)];
#pragma clang diagnostic pop
        if(matches.count == 1) {
            course = [positionPacket substringWithRange:[matches[0] rangeAtIndex:1]].doubleValue;
            speed = [positionPacket substringWithRange:[matches[0] rangeAtIndex:2]].doubleValue * 0.514444;
            positionPacket = [positionPacket substringFromIndex:7];
        }
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        //  PHGR
        commentParser = [NSRegularExpression regularExpressionWithPattern:@"^PHG(\\d[\\x30-\\x7e]\\d\\d[0-9A-Z])/" options:0 error:&error];
        matches = [commentParser matchesInString:positionPacket options:0 range:NSMakeRange(0, positionPacket.length)];
#pragma clang diagnostic pop
        if(matches.count == 1) {
            positionPacket = [positionPacket substringFromIndex:8];
        }
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        // PHG
        commentParser = [NSRegularExpression regularExpressionWithPattern:@"^PHG(\\d[\\x30-\\x7e]\\d\\d)" options:0 error:&error];
        matches = [commentParser matchesInString:positionPacket options:0 range:NSMakeRange(0, positionPacket.length)];
#pragma clang diagnostic pop
        if(matches.count == 1) {
            positionPacket = [positionPacket substringFromIndex:7];
        }
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        // RNG
        commentParser = [NSRegularExpression regularExpressionWithPattern:@"^RNG(\\d{4})" options:0 error:&error];
        matches = [commentParser matchesInString:positionPacket options:0 range:NSMakeRange(0, positionPacket.length)];
#pragma clang diagnostic pop
        if(matches.count == 1) {
            positionPacket = [positionPacket substringFromIndex:7];
        }
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    commentParser = [NSRegularExpression regularExpressionWithPattern:@"^(.*?)/A=(-\\d{5}|\\d{6})(.*)$" options:0 error:&error];
    matches = [commentParser matchesInString:positionPacket options:0 range:NSMakeRange(0, positionPacket.length)];
#pragma clang diagnostic pop
    if(matches.count == 1) {
        altitude = [positionPacket substringWithRange:[matches[0] rangeAtIndex:2]].doubleValue * 0.3048;
        verticalAccuracy = resolution * 1.5;
        // positionPacket = [[positionPacket substringWithRange:[matches[0] rangeAtIndex:1]] stringByAppendingString:[positionPacket substringWithRange:[matches[0] rangeAtIndex:3]]];
    }

    CLLocation *location = [[CLLocation alloc] initWithCoordinate: coordinate
                                                         altitude: altitude
                                               horizontalAccuracy: resolution
                                                 verticalAccuracy: verticalAccuracy
                                                           course: course
                                                            speed: speed
                                                        timestamp: [NSDate date]];
    NSAssert(location != nil, @"Location is nil");
    return location;
}

-(CLLocation *) locationFromNmeaSentence:(NSString *)nmeaSentence {
    NSError *error = nil;
    
    nmeaSentence = [nmeaSentence stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    NSRegularExpression *parser = [NSRegularExpression regularExpressionWithPattern:@"^\\$([\\x20-\\x7e]+)\\*([0-9A-F]{2})$" options:NSRegularExpressionCaseInsensitive error:&error];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    if([parser numberOfMatchesInString:nmeaSentence options:0 range:NSMakeRange(0, nmeaSentence.length)] != 1)
        return nil;
    
    NSTextCheckingResult *match = [parser firstMatchInString:nmeaSentence options:0 range:NSMakeRange(0, nmeaSentence.length)];
#pragma clang diagnostic pop
    unsigned int checksum;
    NSScanner *sumScanner = [NSScanner scannerWithString:[nmeaSentence substringWithRange:[match rangeAtIndex:2]]];
    if(![sumScanner scanHexInt:&checksum]) {
        NSLog(@"Couldn't parse checksum");
        return nil;
    }
    
    NSString *checksumString = [nmeaSentence substringWithRange:[match rangeAtIndex:1]];
    size_t maxLength = [checksumString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    unsigned char *bytes = malloc(maxLength);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    [checksumString getBytes:bytes maxLength:maxLength usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, checksumString.length) remainingRange:NULL];
#pragma clang diagnostic pop
    unsigned char calcSum = nmea_calc_sum(bytes, maxLength);
    free(bytes);
    
    if((unsigned char) checksum != calcSum)
        return nil;

    NSArray <NSString *> *nmeaFields = [checksumString componentsSeparatedByString:@","];
    if([nmeaFields[0] isEqualToString:@"GPRMC"]) {
        if(nmeaFields.count < 10)
            return nil;
        
        //  No fix
        if(![nmeaFields[2] isEqualToString:@"A"])
            return nil;
        
        NSDateComponents *timestampComponents = [[NSDateComponents alloc] init];
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSRegularExpression *timeParser = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d{2})(\\d{2})(\\d{2})(|\\.\\d+)\\s*$" options:0 error:&error];
        NSArray <NSTextCheckingResult *> *matches = [timeParser matchesInString:nmeaFields[1] options:0 range:NSMakeRange(0, nmeaFields[1].length)];
#pragma clang diagnostic pop
        if(matches.count != 1)
            return nil;
        
        timestampComponents.hour = [nmeaFields[1] substringWithRange:[matches[0] rangeAtIndex:1]].integerValue;
        timestampComponents.minute = [nmeaFields[1] substringWithRange:[matches[0] rangeAtIndex:2]].integerValue;
        timestampComponents.second = [nmeaFields[1] substringWithRange:[matches[0] rangeAtIndex:3]].integerValue;
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSRegularExpression *dateParser = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d{2})(\\d{2})(\\d{2})\\s*$" options:0 error:&error];
        matches = [dateParser matchesInString:nmeaFields[9] options:0 range:NSMakeRange(0, nmeaFields[9].length)];
#pragma clang diagnostic pop
        if(matches.count != 1)
            return nil;
        timestampComponents.year = [nmeaFields[9] substringWithRange:[matches[0] rangeAtIndex:1]].integerValue;
        timestampComponents.month = [nmeaFields[9] substringWithRange:[matches[0] rangeAtIndex:2]].integerValue;
        timestampComponents.day = [nmeaFields[9] substringWithRange:[matches[0] rangeAtIndex:3]].integerValue;
        if(timestampComponents.year >= 70)
            timestampComponents.year += 2000;
        else
            timestampComponents.year += 1900;

        NSCalendar *utcCalendar = [NSCalendar currentCalendar];
        utcCalendar.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        NSDate *timestamp = [utcCalendar dateFromComponents:timestampComponents];
        
        if(!timestamp)
            return nil;
        
        double speed = 0.0;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSRegularExpression *speedParser = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d+(|\\.\\d+))\\s*$" options:0 error:&error];
        matches = [speedParser matchesInString:nmeaFields[7] options:0 range:NSMakeRange(0, nmeaFields[7].length)];
#pragma clang diagnostic pop
        if(matches.count == 1)
            speed = [nmeaFields[7] substringWithRange:[matches[0] rangeAtIndex:1]].doubleValue * 0.514444;
        
        double course = 0.0;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSRegularExpression *courseParser = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d+(|\\.\\d+))\\s*$" options:0 error:&error];
        matches = [courseParser matchesInString:nmeaFields[8] options:0 range:NSMakeRange(0, nmeaFields[8].length)];
#pragma clang diagnostic pop
        if(matches.count == 1)
            course = [nmeaFields[8] substringWithRange:[matches[0] rangeAtIndex:1]].doubleValue;
        
        CLLocationCoordinate2D coordinate = {
            .latitude = [self coordinatesFromNmeaString:nmeaFields[3] withSign:nmeaFields[4]],
            .longitude = [self coordinatesFromNmeaString:nmeaFields[5] withSign:nmeaFields[6]]
        };
        
        return [[CLLocation alloc] initWithCoordinate: coordinate
                                             altitude: 0.0
                                   horizontalAccuracy: 100.0
                                     verticalAccuracy: -1.0
                                               course: course
                                                speed: speed
                                            timestamp: timestamp];
    } else if([nmeaFields[0] isEqualToString:@"GPGGA"]) {
        if(nmeaFields.count < 11)
            return nil;
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSRegularExpression *validityParser = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d+)\\s*$" options:0 error:&error];
        NSArray <NSTextCheckingResult *> *matches = [validityParser matchesInString:nmeaFields[6] options:0 range:NSMakeRange(0, nmeaFields[6].length)];
#pragma clang diagnostic pop
        if(matches.count != 1)
            return nil;
        
        if([nmeaFields[6] substringWithRange:[matches[0] rangeAtIndex:1]].integerValue < 1)
            return nil;
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSRegularExpression *timeParser = [NSRegularExpression regularExpressionWithPattern:@"\\.\\d+$" options:0 error:&error];
        NSString *timeString = [timeParser stringByReplacingMatchesInString:nmeaFields[1] options:0 range:NSMakeRange(0, nmeaFields[1].length) withTemplate:@""];
#pragma clang diagnostic pop
        
        NSDate *timestamp = [self dateFromARPSTimestamp:[timeString stringByAppendingString:@"h"]];
                                
        CLLocationCoordinate2D coordinate = {
            .latitude = [self coordinatesFromNmeaString:nmeaFields[2] withSign:nmeaFields[3]],
            .longitude = [self coordinatesFromNmeaString:nmeaFields[4] withSign:nmeaFields[5]]
        };

        double altitude = 0.0;
        if([nmeaFields[10] isEqualToString:@"M"]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
            NSRegularExpression *altitudeParser = [NSRegularExpression regularExpressionWithPattern:@"^(-?\\d+(|\\.\\d+))$" options:0 error:&error];
            matches = [altitudeParser matchesInString:nmeaFields[9] options:0 range:NSMakeRange(0, nmeaFields[9].length)];
#pragma clang diagnostic pop
            if(matches.count != 1)
                return nil;
            
            altitude = [nmeaFields[9] substringWithRange:[matches[0] rangeAtIndex:1]].doubleValue;
        }
        
        return [[CLLocation alloc] initWithCoordinate: coordinate
                                             altitude: altitude
                                   horizontalAccuracy: 100.0
                                     verticalAccuracy: 10.0
                                               course: 0.0
                                                speed: 0.0
                                            timestamp: timestamp];
    }
    
    return nil;
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

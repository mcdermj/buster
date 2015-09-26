//
//  BTRAprsLocation.m
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


#import "BTRAprsLocation.h"

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

@interface BTRAprsLocation ()

@end

@implementation BTRAprsLocation

@dynamic tnc2Packet;

-(id) init {
    self = [super init];
    if(self) {
        _callsign = nil;
        _symbol = '[';
        _symbolTable = '/';
    }
    
    return self;
}

#pragma mark - Accessors

+(NSSet *)keyPathsForValuesTnc2Packet {
    return [NSSet setWithObjects:@"location", nil];
}

-(NSString *)tnc2Packet {
    if(!self.callsign || !self.location)
        return nil;
    
    NSString *tnc2Header = [NSString stringWithFormat:@"%@>APBSTR,DSTAR*:", self.callsign];
 
    NSString *dateString = [self aprsTimestampFromDate:self.location.timestamp];
    NSAssert(dateString != nil, @"Datestring returned nil");
    
    int latDegrees = (int) fabs(self.location.coordinate.latitude);
    double latMinutes = (fabs(self.location.coordinate.latitude) - (double) latDegrees) * 60.0;
    char latDirection = self.location.coordinate.latitude < 0 ? 'S' : 'N';
    int lonDegrees = (int) fabs(self.location.coordinate.longitude);
    double lonMinutes = (fabs(self.location.coordinate.longitude) - (double) lonDegrees) * 60.0;
    char lonDirection = self.location.coordinate.longitude < 0 ? 'W' : 'E';
    NSString *position = [NSString stringWithFormat:@"@%@z%02d%05.2f%c%c%03d%05.2f%c%c", dateString, latDegrees, latMinutes, latDirection, self.symbolTable, lonDegrees, lonMinutes, lonDirection, self.symbol];
    
    int commentChars = 43;
    if((self.location.course >= 0.0 && self.location.course < 360.0) || self.location.speed >= 0.0) {
        NSString *cseSpd = [NSString stringWithFormat:@"%03.0f/%03.0f", self.location.course, self.location.speed * 1.94384];
        position = [position stringByAppendingString:cseSpd];
        commentChars -= cseSpd.length;
    }
    
    if(self.location.verticalAccuracy > 0) {
        NSString *alt = [NSString stringWithFormat:@"/A=%06.0f", self.location.altitude * 3.28084];
        position = [position stringByAppendingString:alt];
        commentChars -= alt.length;
    }
    
    if(self.comment) {
        if(self.comment.length > commentChars)
            position = [position stringByAppendingString:[self.comment substringToIndex:commentChars]];
        else
            position = [position stringByAppendingString:self.comment];
    }
    
    return [NSString stringWithFormat:@"%@%@\r", tnc2Header, position];
}

+(NSSet *)keyPathsForValuesDprsPacket {
    return [BTRAprsLocation keyPathsForValuesTnc2Packet];
}

-(NSString *)dprsPacket {
    NSString *dprsPacket = self.tnc2Packet;
    
    size_t maxLength = [dprsPacket lengthOfBytesUsingEncoding:NSASCIIStringEncoding];
    unsigned char *bytes = malloc(maxLength);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    [dprsPacket getBytes:bytes maxLength:maxLength usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, dprsPacket.length) remainingRange:NULL];
#pragma clang diagnostic pop
    unsigned int crc = gps_calc_sum(bytes, maxLength);
    
    return [NSString stringWithFormat:@"$CRC%04X,%@", crc, dprsPacket];
}

#pragma mark - MKPlacemark protocol implementation

+(NSSet *)keyPathsForValuesAffectingCoordinate {
    return [NSSet setWithObjects:@"location", nil];
}

-(CLLocationCoordinate2D)coordinate {
    return self.location.coordinate;
}

#pragma mark - APRS Parsing

-(NSString *)aprsTimestampFromDate:(NSDate *)date {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    dateFormatter.dateFormat = @"ddHHmm";
    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    
    return [dateFormatter stringFromDate:self.location.timestamp];
}

-(NSString *)aprsCoordinateFromLocation:(NSDate *)date {
    
    return nil;
}

-(NSDate *)dateFromAprsTimestamp:(NSString *)timestamp {
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

-(id) initWithAprsPacket:(NSString *)aprsPacket {
    self = [super init];
    if(self) {
        NSError *error = nil;
        
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
        
        NSString *header = components[0];
        NSRegularExpression *headerParser = [NSRegularExpression regularExpressionWithPattern:@"([A-Z0-9-]{1,9})>(AP[A-Z0-9-]{1,4}),DSTAR\\*" options:NSRegularExpressionCaseInsensitive error:&error];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        matches = [headerParser matchesInString:header options:0 range:NSMakeRange(0, header.length)];
#pragma clang diagnostic pop
        if(matches.count != 1)
            return nil;
        self.callsign = [header substringWithRange:[matches[0] rangeAtIndex:1]];
        
        NSString *body = [[components subarrayWithRange:NSMakeRange(1, components.count -1)] componentsJoinedByString:@""];
        
        NSString *packetType = [body substringWithRange:NSMakeRange(0, 1)];
        if([packetType isEqualToString:@"!"] ||
           [packetType isEqualToString:@"="] ||
           [packetType isEqualToString:@"/"] ||
           [packetType isEqualToString:@"@"]) {
            //  Position Packet
            NSDate *timestamp = [NSDate date];
            //  If packetTyep == ! or /, messaging == yes, these shouldn't be received on DSTAR.
            
            if(body.length < 14)
                return nil;
            
            if([packetType isEqualToString:@"/"] ||
               [packetType isEqualToString:@"@"]) {
                timestamp = [self dateFromAprsTimestamp:[body substringWithRange:NSMakeRange(1, 7)]];
                if([timestamp isEqualToDate:[NSDate distantPast]])
                    timestamp = [NSDate date];
                body = [body substringFromIndex:7];
            }
            
            body = [body substringFromIndex:1];
            if(![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[body characterAtIndex:1]])
                return nil;
            
            if(body.length < 19)
                return nil;
            
            //  Parse the APRS position meat
            CLLocation *position = [self locationFromAprsPositionPacket:[body stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]];
            if(!position)
                return nil;
            _location = [[CLLocation alloc] initWithCoordinate:position.coordinate
                                                      altitude:position.altitude
                                            horizontalAccuracy:position.horizontalAccuracy
                                              verticalAccuracy:position.verticalAccuracy
                                                        course:position.course
                                                         speed:position.speed
                                                     timestamp:timestamp];
        } else if([packetType isEqualToString:@";"]) {
            //  Object
            if(body.length < 31)
                return nil;
            
            _location = [[CLLocation alloc] initWithLatitude:0.0 longitude:0.0];
        } else if([packetType isEqualToString:@">"]) {
            //  Status Report
            
            _location = [[CLLocation alloc] initWithLatitude:0.0 longitude:0.0];
        } else {
            // Unknown packet
            return nil;
        }
    }
    
    return self;
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
    NSString *symbolCode = [positionPacket substringWithRange:[matches[0] rangeAtIndex:8]];
    
    if(![[NSCharacterSet characterSetWithCharactersInString:@"\\/ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"] characterIsMember:[symbolTable characterAtIndex:0]]) {
        //  Invalid symbol table
        return nil;
    }
    
    self.symbolTable = (char) [symbolTable characterAtIndex:0];
    self.symbol = (char) [symbolCode characterAtIndex:0];
    
    if(latDeg > 89.0 || lonDeg > 179.0)
        return nil;
    
    NSString *tmpLat = [latMin stringByReplacingOccurrencesOfString:@"." withString:@""];  //  I don't know why we're doing this
    NSInteger posAmbiguity = tmpLat.length - [tmpLat stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length;
    
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

#pragma mark - NMEA Parsing

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

-(id) initWithNmeaSentence:(NSString *)nmeaSentence {
    self = [super init];
    if(self) {
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
            
            _location = [[CLLocation alloc] initWithCoordinate: coordinate
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
            
            NSDate *timestamp = [self dateFromAprsTimestamp:[timeString stringByAppendingString:@"h"]];
            
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
            
            _location = [[CLLocation alloc] initWithCoordinate: coordinate
                                                 altitude: altitude
                                       horizontalAccuracy: 100.0
                                         verticalAccuracy: 10.0
                                                   course: 0.0
                                                    speed: 0.0
                                                timestamp: timestamp];
        }
    }
    
    return self;
}

@end

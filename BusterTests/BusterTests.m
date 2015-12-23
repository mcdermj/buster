/*
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at
 * https://solaris.java.net/license.html
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at
 * https://solaris.java.net/license.html.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
 * License for the specific language governing permissions and limitations under
 * the License.
 *
 * Copyright (c) 2015 Jeremy McDermond (NH6Z). All rights reserved.
 *
 */

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>

#import "BTRAprsLocation.h"
#import "BTRSlowDataCoder.h"

@interface BusterTests : XCTestCase

@end

@implementation BusterTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

-(void)testNMEAParser {
    NSError *error;
    //  Test for good NMEA sentences
    NSString *nmeaCorpus = [NSString stringWithContentsOfURL:[[NSBundle bundleForClass:[self class]] URLForResource:@"nmeacorpus" withExtension:@"txt"] encoding:NSASCIIStringEncoding error:&error];
    
    NSArray <NSString *> *corpusLines = [nmeaCorpus componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    for(NSString *line in corpusLines) {
        BTRAprsLocation *location = [[BTRAprsLocation alloc] initWithNmeaSentence:line];
        XCTAssertNotNil(location, @"Good NMEA sentence not parsed: %@", line);
    }
    
    //  Test for bad NMEA sentences
    NSArray <NSString *> *badCorpusLines = [[NSString stringWithContentsOfURL:[[NSBundle bundleForClass:[self class]] URLForResource:@"nmeabadcorpus" withExtension:@"txt"] encoding:NSASCIIStringEncoding error:&error] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    for(NSString *line in badCorpusLines) {
        BTRAprsLocation *location = [[BTRAprsLocation alloc] initWithNmeaSentence:line];
        XCTAssertNil(location, @"Bad NMEA sentence succeeded: %@", line);
    }
}

-(void)testAPRSParser {
    NSError *error;
    
    NSArray <NSString *> *corpusLines = [[NSString stringWithContentsOfURL:[[NSBundle bundleForClass:[self class]] URLForResource:@"aprschecksumcorpus" withExtension:@"txt"] encoding:NSASCIIStringEncoding error:&error] componentsSeparatedByString:@"\n"];

    for(NSString *line in corpusLines) {
        if([line isEqualToString:@""])
            continue;
        
        BTRAprsLocation *location = [[BTRAprsLocation alloc] initWithAprsPacket:line];
        XCTAssertNotNil(location, @"Good APRS Sentence not parsed: %@", line);
    }
}

-(void)testAprsEncoder {
    BTRAprsLocation *location = [[BTRAprsLocation alloc] init];
    CLLocationCoordinate2D coordinates = {
        .latitude = 50.0,
        .longitude = 50.0
    };
    
    XCTAssertNil(location.tnc2Packet, @"Position returned without callsign or location");
    
    location.callsign = @"NH6Z";
    
    XCTAssertNil(location.tnc2Packet, @"Position returned without a location");
    
    location.location = [[CLLocation alloc] initWithLatitude:50.0 longitude:50.0];
    
    XCTAssertNotNil(location.tnc2Packet, @"Position not returned with valid callsign and location");
    
    location.callsign = nil;
    
    XCTAssertNil(location.tnc2Packet, @"Position returned without a callsign");
    
    location.callsign = @"NH6Z";
    location.location = [[CLLocation alloc] initWithCoordinate: coordinates altitude:0.0 horizontalAccuracy:5.0 verticalAccuracy:-1.0 course:0.0 speed:0.0 timestamp:[NSDate date]];
    XCTAssertNotNil(location.tnc2Packet, @"Position not returned with extended location");
    XCTAssert([location.tnc2Packet rangeOfString:@"000/000"].location == NSNotFound, @"Course returned when zeros: %@", location.tnc2Packet);
    XCTAssert([location.tnc2Packet rangeOfString:@"/A=000000"].location == NSNotFound, @"Altitude found when accuracy is negative: %@", location.tnc2Packet);
    
    NSLog(@"length = %ld", location.tnc2Packet.length);
    
    location.location = [[CLLocation alloc] initWithCoordinate: coordinates altitude:50.0 horizontalAccuracy:5.0 verticalAccuracy:10.0 course:0.0 speed:0.0 timestamp:[NSDate date]];
    XCTAssertNotNil(location.tnc2Packet, @"Position not returned with extended location");
    XCTAssert([location.tnc2Packet rangeOfString:@"000/000"].location == NSNotFound, @"Course returned when zeros: %@", location.tnc2Packet);
    XCTAssertFalse([location.tnc2Packet rangeOfString:@"/A=000164"].location == NSNotFound, @"Altitude not found: %@", location.tnc2Packet);
    
    location.location = [[CLLocation alloc] initWithCoordinate: coordinates altitude:50.0 horizontalAccuracy:5.0 verticalAccuracy:10.0 course:100.0 speed:0.0 timestamp:[NSDate date]];
    XCTAssertNotNil(location.tnc2Packet, @"Position not returned with extended location");
    XCTAssertFalse([location.tnc2Packet rangeOfString:@"100/000"].location == NSNotFound, @"Course not returned: %@", location.tnc2Packet);
    XCTAssertFalse([location.tnc2Packet rangeOfString:@"/A=000164"].location == NSNotFound, @"Altitude not returned: %@", location.tnc2Packet);

    location.location = [[CLLocation alloc] initWithCoordinate: coordinates altitude:50.0 horizontalAccuracy:5.0 verticalAccuracy:10.0 course:100.0 speed:100.0 timestamp:[NSDate date]];
    XCTAssertNotNil(location.tnc2Packet, @"Position not returned with extended location");
    XCTAssertFalse([location.tnc2Packet rangeOfString:@"100/194"].location == NSNotFound, @"Course not returned: %@", location.tnc2Packet);
    XCTAssertFalse([location.tnc2Packet rangeOfString:@"/A=000164"].location == NSNotFound, @"Altitude not returned: %@", location.tnc2Packet);

    location.location = [[CLLocation alloc] initWithCoordinate: coordinates altitude:50.0 horizontalAccuracy:5.0 verticalAccuracy:10.0 course:0.0 speed:100.0 timestamp:[NSDate date]];
    XCTAssertNotNil(location.tnc2Packet, @"Position not returned with extended location");
    XCTAssertFalse([location.tnc2Packet rangeOfString:@"000/194"].location == NSNotFound, @"Course not returned: %@", location.tnc2Packet);
    XCTAssertFalse([location.tnc2Packet rangeOfString:@"/A=000164"].location == NSNotFound, @"Altitude not returned: %@", location.tnc2Packet);
    
    location.location = [[CLLocation alloc] initWithCoordinate: coordinates altitude:50.0 horizontalAccuracy:5.0 verticalAccuracy:-1.0 course:100.0 speed:0.0 timestamp:[NSDate date]];
    XCTAssertNotNil(location.tnc2Packet, @"Position not returned with extended location");
    XCTAssertFalse([location.tnc2Packet rangeOfString:@"100/000"].location == NSNotFound, @"Course not returned: %@", location.tnc2Packet);
    XCTAssert([location.tnc2Packet rangeOfString:@"/A=000164"].location == NSNotFound, @"Altitude found when accuracy is negative: %@", location.tnc2Packet);
    
    location.location = [[CLLocation alloc] initWithCoordinate: coordinates altitude:50.0 horizontalAccuracy:5.0 verticalAccuracy:-1.0 course:100.0 speed:100.0 timestamp:[NSDate date]];
    XCTAssertNotNil(location.tnc2Packet, @"Position not returned with extended location");
    XCTAssertFalse([location.tnc2Packet rangeOfString:@"100/194"].location == NSNotFound, @"Course not returned: %@", location.tnc2Packet);
    XCTAssert([location.tnc2Packet rangeOfString:@"/A=000164"].location == NSNotFound, @"Altitude found when accuracy is negative: %@", location.tnc2Packet);
    
    location.location = [[CLLocation alloc] initWithCoordinate: coordinates altitude:50.0 horizontalAccuracy:5.0 verticalAccuracy:10.0 course:100.0 speed:100.0 timestamp:[NSDate date]];
    location.comment = [@"" stringByPaddingToLength:26 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 42, @"Comment not right length: %ld", location.tnc2Packet.length - 46);
    location.comment = [@"" stringByPaddingToLength:27 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 43, @"Comment too long: %ld", location.tnc2Packet.length - 46);
    location.comment = [@"" stringByPaddingToLength:28 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 43, @"Comment too long: %ld", location.tnc2Packet.length - 46);
    location.comment = [@"" stringByPaddingToLength:29 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 43, @"Comment too long: %ld", location.tnc2Packet.length - 46);
    
    location.location = [[CLLocation alloc] initWithCoordinate: coordinates altitude:50.0 horizontalAccuracy:5.0 verticalAccuracy:-1.0 course:100.0 speed:100.0 timestamp:[NSDate date]];
    location.comment = [@"" stringByPaddingToLength:35 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 42, @"Comment not right length: %ld", location.tnc2Packet.length - 46);
    location.comment = [@"" stringByPaddingToLength:36 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 43, @"Comment too long: %ld", location.tnc2Packet.length - 46);
    location.comment = [@"" stringByPaddingToLength:37 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 43, @"Comment too long: %ld", location.tnc2Packet.length - 46);
    location.comment = [@"" stringByPaddingToLength:38 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 43, @"Comment too long: %ld", location.tnc2Packet.length - 46);
    
    location.location = [[CLLocation alloc] initWithCoordinate: coordinates altitude:50.0 horizontalAccuracy:5.0 verticalAccuracy:10.0 course:0.0 speed:0.0 timestamp:[NSDate date]];
    location.comment = [@"" stringByPaddingToLength:33 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 42, @"Comment not right length: %ld", location.tnc2Packet.length - 46);
    location.comment = [@"" stringByPaddingToLength:34 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 43, @"Comment too long: %ld", location.tnc2Packet.length - 46);
    location.comment = [@"" stringByPaddingToLength:35 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 43, @"Comment too long: %ld", location.tnc2Packet.length - 46);
    location.comment = [@"" stringByPaddingToLength:36 withString:@"X" startingAtIndex:0];
    XCTAssert(location.tnc2Packet.length - 46 == 43, @"Comment too long: %ld", location.tnc2Packet.length - 46);
    
    NSLog(@"DPlus Packet = %@", location.dprsPacket);
}

-(void)testPositionEncoder {
    BTRSlowDataCoder *testCoder = [[BTRSlowDataCoder alloc] init];
    CLLocation *location = [[CLLocation alloc] initWithLatitude:50.0 longitude:50.0];
    
    [testCoder locationManager:nil didUpdateLocations:@[ location ]];
}
@end

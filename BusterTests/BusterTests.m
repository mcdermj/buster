//
//  BusterTests.m
//  BusterTests
//
//  Created by Jeremy McDermond on 7/10/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>

#import "BTRSlowDataCoder.h"

@interface BTRSlowDataCoder (XCTests)
-(CLLocation *) locationFromNmeaSentence:(NSString *)nmeaSentence;
-(CLLocation *) locationFromAprsPacket:(NSString *)aprsPacket;
@end

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
    BTRSlowDataCoder *testCoder = [[BTRSlowDataCoder alloc] init];
    
    //  Test for good NMEA sentences
    NSString *nmeaCorpus = [NSString stringWithContentsOfURL:[[NSBundle bundleForClass:[self class]] URLForResource:@"nmeacorpus" withExtension:@"txt"] encoding:NSASCIIStringEncoding error:&error];
    
    NSArray <NSString *> *corpusLines = [nmeaCorpus componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    for(NSString *line in corpusLines) {
        CLLocation *location = [testCoder locationFromNmeaSentence:line];
        XCTAssertNotNil(location, @"Good NMEA sentence not parsed: %@", line);
    }
    
    //  Test for bad NMEA sentences
    NSArray <NSString *> *badCorpusLines = [[NSString stringWithContentsOfURL:[[NSBundle bundleForClass:[self class]] URLForResource:@"nmeabadcorpus" withExtension:@"txt"] encoding:NSASCIIStringEncoding error:&error] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    for(NSString *line in badCorpusLines) {
        CLLocation *location = [testCoder locationFromNmeaSentence:line];
        XCTAssertNil(location, @"Bad NMEA sentence succeeded: %@", line);
    }
}

-(void)testAPRSParser {
    NSError *error;
    BTRSlowDataCoder *testCoder = [[BTRSlowDataCoder alloc] init];
    
    NSArray <NSString *> *corpusLines = [[NSString stringWithContentsOfURL:[[NSBundle bundleForClass:[self class]] URLForResource:@"aprschecksumcorpus" withExtension:@"txt"] encoding:NSASCIIStringEncoding error:&error] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    for(NSString *line in corpusLines) {
        if([line isEqualToString:@""])
            continue;
        
        CLLocation *location = [testCoder locationFromAprsPacket:line];
        XCTAssertNotNil(location, @"Good APRS Sentence not parsed: %@", line);
    }
}
@end

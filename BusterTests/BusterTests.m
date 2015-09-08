//
//  BusterTests.m
//  BusterTests
//
//  Created by Jeremy McDermond on 7/10/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>

#import "BTRAprsLocation.h"

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
@end

//
//  BTRDataEngine.m
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


#import "BTRDataEngine.h"

#import "BTRDV3KSerialVocoder.h"
#import "BTRDV3KNetworkVocoder.h"
#import "BTRAudioHandler.h"
#import "BTRSlowDataCoder.h"
#import "BTRDPlusLink.h"
#import "BTRDExtraLink.h"

static NSMutableArray *vocoderDrivers = nil;
static NSMutableArray <Class> *linkDriverClasses = nil;

@interface BTRDataEngine ()

@property (nonatomic, readwrite) NSObject <BTRLinkDriverProtocol> *network;
@property (nonatomic, readwrite) BTRAudioHandler *audio;
@property (nonatomic, copy) NSString *sleepDestination;
@property (nonatomic, readonly) NSArray <id <BTRLinkDriverProtocol>> *linkDrivers;
@property (nonatomic, readonly) dispatch_queue_t linkQueue;
@end

@implementation BTRDataEngine

+ (BTRDataEngine *) sharedInstance {
    static BTRDataEngine *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

-(id) init {
    self = [super init];
    if(self) {
        _audio = [[BTRAudioHandler alloc] init];
        _network = nil;
        Class vocoderDriver = NSClassFromString([[NSUserDefaults standardUserDefaults] stringForKey:@"VocoderDriver"]);
        self.vocoder = [[vocoderDriver alloc] init];
        
        _vocoder.audio = _audio;
        
        _slowData = [[BTRSlowDataCoder alloc] init];
        _slowData.delegate = self;
        
        //  Instantiate all the link drivers
        _linkQueue = dispatch_queue_create("net.nh6z.Buster.LinkOperations", DISPATCH_QUEUE_SERIAL);
        NSMutableArray <id <BTRLinkDriverProtocol>> *newLinkDrivers = [[NSMutableArray alloc] init];
        for(Class driver in linkDriverClasses) {
            NSObject <BTRLinkDriverProtocol> *newDriver = [[driver alloc] init];
            [newLinkDrivers addObject:newDriver];
            newDriver.linkQueue = self.linkQueue;
            newDriver.delegate = self;
            [newDriver bind:@"myCall" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.myCall" options:nil];
            [newDriver bind:@"myCall2" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.myCall2" options:nil];
        }
        _linkDrivers = [NSArray arrayWithArray:newLinkDrivers];
        
        BTRDataEngine __weak *weakSelf = self;
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceWillSleepNotification object:NULL queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
            [weakSelf.audio stop];
            [weakSelf.vocoder stop];
            weakSelf.sleepDestination = weakSelf.network.linkTarget;
            [weakSelf.network unlink];
        }];
        
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidWakeNotification object:NULL queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
            [weakSelf.audio start];
            [weakSelf.vocoder start];
            [weakSelf linkTo:self.sleepDestination];
        }];        
    }
    
    return self;
}

-(void) dealloc {
}

- (void) setVocoder:(id<BTRVocoderDriver>)vocoder {
    _vocoder = vocoder;
    
    self.network.vocoder = vocoder;
    self.audio.vocoder = vocoder;
    self.vocoder.audio = self.audio;
    self.vocoder.network = self.network;
}

+(void)registerVocoderDriver:(Class)driver {
    if(!vocoderDrivers)
        vocoderDrivers = [[NSMutableArray alloc] init];
    
    [vocoderDrivers addObject:driver];
}

+(void)registerLinkDriver:(Class)driver {
    if(!linkDriverClasses)
        linkDriverClasses = [[NSMutableArray alloc] init];
    
    [linkDriverClasses addObject:driver];
}

+(NSArray *)vocoderDrivers {
    return [NSArray arrayWithArray:vocoderDrivers];
}

-(BOOL)isDestinationValid:(NSString *)destination {
    NSUInteger linkIndex = [self.linkDrivers indexOfObjectPassingTest:^BOOL(id <BTRLinkDriverProtocol> obj, NSUInteger idx, BOOL *stop) {
        BOOL test = [obj canHandleLinkTo:destination];
        if(test)
            *stop = YES;
        
        return test;
    }];
    
    return(linkIndex != NSNotFound);
}

-(void)linkTo:(NSString *)reflector {
    if(!reflector)
        return;
    
    if([self.network.linkTarget isEqualToString:reflector])
        return;
    
    [self unlink];
    
    for(NSObject <BTRLinkDriverProtocol> *driver in self.linkDrivers) {
        if([driver canHandleLinkTo:reflector]) {
            self.network = driver;
            [driver linkTo:reflector];
            self.network.vocoder = self.vocoder;
            self.vocoder.network = self.network;
            break;
        }
    }
    
    if(self.network == nil) {
        NSError *error = [NSError errorWithDomain:@"BTRErrorDomain" code:2 userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ does not exist.", reflector]}];
        [self.delegate destinationDidError:reflector error:error];
        NSLog(@"Sending link failed notification");
    }
}

-(void)unlink {
        if(self.network) {
            [self.network unlink];
            self.network = nil;
            self.vocoder.network = nil;
        }
}

-(void)streamDidStart:(NSDictionary *)header {
    self.audio.receiving = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate streamDidStart:header];
    });
}

-(void)streamDidEnd:(NSNumber *)streamId atTime:(NSDate *)time {
    self.audio.receiving = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate streamDidEnd:streamId atTime:time];
    });
}
-(void)slowDataReceived:(NSString *)slowData forStreamId:(NSNumber *)streamId {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate slowDataReceived:slowData forStreamId:streamId];
    });
}

-(void)locationReceived:(CLLocation *)location forStreamId:(NSNumber *)streamId {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate locationReceived:location forStreamId:streamId];
    });
}

-(void)addData:(void *)data streamId:(NSUInteger)streamId {
    [self.slowData addData:data streamId:streamId];
}

-(void)getBytes:(void *)bytes forSequence:(NSUInteger)sequence {
    return [self.slowData getBytes:bytes forSequence:sequence];
}

-(void)destinationDidLink:(NSString *)destination {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate destinationDidLink:destination];
    });
}

-(void)destinationDidUnlink:(NSString *)destination {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate destinationDidUnlink:destination];
    });
}

-(void)destinationDidConnect:(NSString *)destination {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate destinationDidConnect:destination];
    });
}

-(void)destinationWillLink:(NSString *)destination {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate destinationWillLink:destination];
    });
}

-(void)destinationDidError:(NSString *)destination error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate destinationDidError:destination error:error];
    });
}

@end

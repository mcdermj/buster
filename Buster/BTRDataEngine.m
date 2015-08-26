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
static NSMutableArray *linkDrivers = nil;

@interface BTRDataEngine ()

@property (nonatomic, readwrite) NSObject <BTRLinkDriverProtocol> *network;
@property (nonatomic, readwrite) BTRAudioHandler *audio;
@property (nonatomic, copy) NSString *sleepDestination;
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
        Class driver = NSClassFromString([[NSUserDefaults standardUserDefaults] stringForKey:@"VocoderDriver"]);
        self.vocoder = [[driver alloc] init];
        
        _vocoder.audio = _audio;
        
        _slowData = [[BTRSlowDataCoder alloc] init];
        _slowData.delegate = self;
        
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
    if(!linkDrivers)
        linkDrivers = [[NSMutableArray alloc] init];
    
    [linkDrivers addObject:driver];
}

+(NSArray *)vocoderDrivers {
    return [NSArray arrayWithArray:vocoderDrivers];
}

+(NSArray *)linkDrivers {
    return [NSArray arrayWithArray:linkDrivers];
}

+(BOOL)isDestinationValid:(NSString *)destination {
    NSUInteger linkIndex = [[BTRDataEngine linkDrivers] indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
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
    
    for(Class driver in [BTRDataEngine linkDrivers]) {
        if([driver canHandleLinkTo:reflector]) {
           self.network = [[driver alloc] initWithLinkTo:reflector];
            self.network.vocoder = self.vocoder;
            self.vocoder.network = self.network;
            self.network.delegate = self;
            
            [self.network bind:@"myCall" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.myCall" options:nil];
            [self.network bind:@"myCall2" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.myCall2" options:nil];
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
            [self.network unbind:@"myCall"];
            [self.network unbind:@"myCall2"];
            self.network = nil;
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

-(void)addData:(void *)data streamId:(NSUInteger)streamId {
    [self.slowData addData:data streamId:streamId];
}

-(const void *)getDataForSequence:(NSUInteger)sequence {
    return [self.slowData getDataForSequence:sequence];
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

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

@property (nonatomic, readwrite) id <BTRLinkDriverProtocol> network;
@property (nonatomic, readwrite) BTRAudioHandler *audio;
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
        // _network = [[BTRDExtraLink alloc] init];
        Class driver = NSClassFromString([[NSUserDefaults standardUserDefaults] stringForKey:@"VocoderDriver"]);
        self.vocoder = [[driver alloc] init];
        
        _vocoder.audio = _audio;
        
        _slowData = [[BTRSlowDataCoder alloc] init];
    }
    
    return self;
}

-(void) dealloc {
    //  Need to unlink here.
}

- (void) setVocoder:(id<BTRVocoderDriver>)vocoder {
    _vocoder = vocoder;
    
    self.network.vocoder = vocoder;
    self.audio.vocoder = vocoder;
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

-(void)linkTo:(NSString *)reflector {
    /* if(self.network.linkState != UNLINKED)
        [self.network unlink]; */
    NSLog(@"In LinkTo:");
    for(Class driver in [BTRDataEngine linkDrivers]) {
        if([driver canHandleLinkTo:reflector]) {
            self.network = [[driver alloc] init];
            [self.network linkTo:reflector];
            self.network.vocoder = self.vocoder;
        }
    }
}

@end

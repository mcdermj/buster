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

@interface BTRDataEngine ()

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
        _vocoder = [[BTRDV3KVocoder alloc] init];
        _network = [[BTRGatewayHandler alloc] init];
        
        _network.vocoder = _vocoder;
        _audio.vocoder = _vocoder;
        _vocoder.audio = _audio;
    }
    
    return self;
}

@end

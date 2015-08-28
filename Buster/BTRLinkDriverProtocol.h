//
//  BTRLinkDriver.h
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

#import "BTRVocoderDriver.h"
#import "BTRLinkDriverDelegate.h"

enum linkState {
    UNLINKED,
    CONNECTED,
    LINKING,
    LINKED
};

@protocol BTRLinkDriverProtocol

-(BOOL)canHandleLinkTo:(NSString *)reflector;

@property (nonatomic, readonly, copy) NSString *linkTarget;
@property (nonatomic) id <BTRVocoderDriver> vocoder;
@property (nonatomic, copy)NSString *myCall;
@property (nonatomic, copy)NSString *myCall2;
@property (nonatomic, weak) NSObject <BTRLinkDriverDelegate> *delegate;
@property (nonatomic) dispatch_queue_t linkQueue;

-(void)linkTo:(NSString *)linkTarget;
-(void)unlink;

-(void) sendAMBE:(void *)data lastPacket:(BOOL)last;
@end 

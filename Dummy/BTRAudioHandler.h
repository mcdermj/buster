//
//  BTRAudioHandler.h
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

#import <AudioToolbox/AudioToolbox.h>

@protocol BTRVocoderProtocol;

extern NSString * const BTRAudioDeviceChanged;

@interface BTRAudioHandler : NSObject

-(void) queueAudioData:(void *)audioData withLength:(uint32)length;
-(BOOL) start;
-(void) stop;

+(NSArray *)enumerateInputDevices;
+(NSArray *)enumerateOutputDevices;

-(void)setInputDevice:(AudioDeviceID)_inputDevice andOutputDevice:(AudioDeviceID)_outputDevice;

@property (nonatomic) id<BTRVocoderProtocol> vocoder;
@property (nonatomic) AudioDeviceID inputDevice;
@property (nonatomic) AudioDeviceID outputDevice;
@property (nonatomic, readonly) AudioDeviceID defaultInputDevice;
@property (nonatomic, readonly) AudioDeviceID defaultOutputDevice;
@property (nonatomic) BOOL xmit;

@end

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
 * Copyright (c) 2015 Annaliese McDermond (NH6Z). All rights reserved.
 *
 */

#import <AudioToolbox/AudioToolbox.h>

@protocol BTRVocoderDriver;

extern NSString * const BTRAudioDeviceChanged;

@interface BTRAudioHandler : NSObject

-(void) queueAudioData:(void *)audioData withLength:(uint32)length;
-(BOOL) start;
-(void) stop;

+(NSArray *)enumerateInputDevices;
+(NSArray *)enumerateOutputDevices;

-(void)setInputDevice:(AudioDeviceID)_inputDevice andOutputDevice:(AudioDeviceID)_outputDevice;

@property (nonatomic) id<BTRVocoderDriver> vocoder;
@property (nonatomic) AudioDeviceID inputDevice;
@property (nonatomic) AudioDeviceID outputDevice;
@property (nonatomic, readonly) AudioDeviceID defaultInputDevice;
@property (nonatomic, readonly) AudioDeviceID defaultOutputDevice;
@property (nonatomic) BOOL xmit;
@property (nonatomic) float outputVolume;

@property (nonatomic) BOOL receiving;

@end

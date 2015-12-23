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
@property (nonatomic, readonly) NSArray<NSString *> *destinations;

-(void)linkTo:(NSString *)linkTarget;
-(void)unlink;

-(void) sendAMBE:(void *)data lastPacket:(BOOL)last;
@end 

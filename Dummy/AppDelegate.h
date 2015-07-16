//
//  AppDelegate.h
//  Dummy
//
//  Created by Jeremy McDermond on 7/10/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "DMYGatewayHandler.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (readonly) DMYGatewayHandler *network;

@end


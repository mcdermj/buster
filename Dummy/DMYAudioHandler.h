//
//  DMYAudioHandler.h
//  Dummy
//
//  Created by Jeremy McDermond on 7/16/15.
//  Copyright (c) 2015 NH6Z. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DMYAudioHandler : NSObject

-(void) queueAudioData:(void *)audioData withLength:(uint32)length;
-(BOOL) start;

@end

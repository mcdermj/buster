//
//  BTRMapPopupController.h
//  Buster
//
//  Created by Jeremy McDermond on 9/2/15.
//  Copyright © 2015 NH6Z. All rights reserved.
//

@import MapKit;

@interface BTRMapPopupController : NSViewController <NSPopoverDelegate>

@property (nonatomic) MKPointAnnotation *annotation;
@property (weak) IBOutlet MKMapView *mapView;
@property (nonatomic) NSNumber *qsoId;
@property (nonatomic) BOOL suppressClose;

@end

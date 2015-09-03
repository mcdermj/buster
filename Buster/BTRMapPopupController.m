//
//  BTRMapPopupController.m
//  Buster
//
//  Created by Jeremy McDermond on 9/2/15.
//  Copyright © 2015 NH6Z. All rights reserved.
//

#import "BTRMapPopupController.h"

@interface BTRMapPopupController ()

@end

@implementation BTRMapPopupController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

- (void) viewWillAppear {
    NSLog(@"Got annotation %@", self.annotation);
    [self.mapView addAnnotation:self.annotation];
    MKCoordinateRegion region = {
        .center = self.annotation.coordinate,
        .span = {
            .latitudeDelta = 10.0,
            .longitudeDelta = 10.0
        }
    };
    //self.mapView.centerCoordinate = self.annotation.coordinate;
    self.mapView.region = region;
}

@end

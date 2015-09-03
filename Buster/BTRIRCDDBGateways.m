//
//  BTRIRCDDBGateways.m
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


#import "BTRIRCDDBGateways.h"

@interface BTRIRCDDBGateways ()

@property (nonatomic) NSMutableURLRequest *ircDDBDataRequest;
@property (nonatomic) NSDate *lastModified;
@property (nonatomic) dispatch_source_t pollTimer;

@end

@implementation BTRIRCDDBGateways

-(id)init {
    self = [super init];
    if(self) {
        _ircDDBDataRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://status.ircddb.net/ircddbgw.json"]];
        _lastModified = [NSDate distantPast];

        BTRIRCDDBGateways __weak *weakSelf = self;
        _pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        dispatch_source_set_timer(_pollTimer, dispatch_walltime(NULL, 0), 30ull * 60ull * NSEC_PER_SEC, 60ull * NSEC_PER_SEC);
        dispatch_source_set_event_handler(_pollTimer, ^{
            // XXX Do something with authentication failure here.  NSNotification?
            [weakSelf checkGatewayTable];
        });
        dispatch_resume(_pollTimer);
    }
    return self;
}

-(void)dealloc {
    dispatch_source_cancel(self.pollTimer);
}

-(void)checkGatewayTable {
    BTRIRCDDBGateways __weak *weakSelf = self;
    
    self.ircDDBDataRequest.HTTPMethod = @"HEAD";
    NSURLSessionDataTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:self.ircDDBDataRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        formatter.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        NSDate *lastModified = [formatter dateFromString:((NSHTTPURLResponse *)response).allHeaderFields[@"Last-Modified"]];
        NSLog(@"Last modified: %@", lastModified);
        if([weakSelf.lastModified compare:lastModified] == NSOrderedAscending) {
            NSLog(@"There is new data, fetching...");
            [weakSelf fetchGatewayTable];
            weakSelf.lastModified = lastModified;
        }
        
    }];
    [dataTask resume];
}

-(void)fetchGatewayTable {
    BTRIRCDDBGateways __weak *weakSelf = self;
    
    self.ircDDBDataRequest.HTTPMethod = @"GET";
    NSURLSessionDataTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:self.ircDDBDataRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSError *JSONError;
        
        if(!data)
            return;
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        NSDictionary *JSONResult = [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError];
#pragma clang diagnostic pop
        
        if(JSONResult) {
            NSMutableDictionary *newGateways = [[NSMutableDictionary alloc] init];

            for(NSDictionary *entry in JSONResult[@"ircddbgw"]) {
                if([entry[@"status"] isEqualToString:@"t"]) {
                    NSString *reflectorName = [((NSString *)entry[@"zonerp_cs"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    newGateways[reflectorName] = entry[@"zonerp_ipaddr"];
                }
            }
            
            weakSelf.gateways = [NSDictionary dictionaryWithDictionary:newGateways];
        } else {
            NSLog(@"Cannot unserialize JSON data: %@", JSONError);
        }
    }];
    [dataTask resume];
}

@end

//
//  ObjCException.m
//  Knobler
//

#import "ObjCException.h"

@implementation ObjCException

+ (BOOL)catching:(NS_NOESCAPE void (^)(void))block
           error:(NSError *_Nullable *_Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *e) {
        if (error) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = e.reason ?: e.name;
            info[@"NSExceptionName"] = e.name;
            if (e.reason) { info[@"NSExceptionReason"] = e.reason; }
            *error = [NSError errorWithDomain:@"ObjCException" code:1 userInfo:info];
        }
        return NO;
    }
}

@end

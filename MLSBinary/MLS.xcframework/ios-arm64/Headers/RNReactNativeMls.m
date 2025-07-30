#import "RNReactNativeMls.h"
#import "MLSModule.h"

@implementation RNReactNativeMls

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

// This is a compatibility wrapper that forwards to MLSModule
// It's kept for backward compatibility but doesn't implement any methods
// All functionality is implemented in MLSModule

@end
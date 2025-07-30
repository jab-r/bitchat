#if __has_include("RCTBridgeModule.h")
#import "RCTBridgeModule.h"
#else
#import <React/RCTBridgeModule.h>
#endif

/**
 * This is a compatibility wrapper that forwards to MLSModule
 * It's kept for backward compatibility but doesn't implement any methods
 * All functionality is implemented in MLSModule
 */
@interface RNReactNativeMls : NSObject <RCTBridgeModule>

@end
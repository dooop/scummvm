//
//  ScummVMEngine.h
//  ScummVM
//
//  Created by Dominic Opitz on 2/14/25.
//

#import <Foundation/Foundation.h>
#if TARGET_OS_IOS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#elif TARGET_OS_MAC
#import <AppKit/AppKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class ScummVMEngine;

#ifdef __cplusplus
extern "C" {
#endif
FOUNDATION_EXPORT ScummVMEngine *ScummVMEngineSharedInstance(void);
#ifdef __cplusplus
}
#endif

@interface ScummVMEngine : NSObject

+ (ScummVMEngine *)sharedInstance;
- (void)start;
- (void)stop;

#if TARGET_OS_IOS || TARGET_OS_TV
- (nullable UIViewController *)ui;
#elif TARGET_OS_MAC
- (nullable NSWindow *)ui;
#endif

@end

NS_ASSUME_NONNULL_END

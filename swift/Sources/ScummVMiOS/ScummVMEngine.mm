//
//  ScummVMEngine.mm
//  ScummVM
//
//  Created by Dominic Opitz on 2/14/25.
//

#import "include/ScummVMEngine.h"
#import "ScummVMAppContext.h"

ScummVMEngine *ScummVMEngineSharedInstance(void) {
    static ScummVMEngine *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ScummVMEngine alloc] init];
    });
    return sharedInstance;
}

@implementation ScummVMEngine

+ (instancetype)sharedInstance {
    return ScummVMEngineSharedInstance();
}

- (void)start {
    [self startWithGamePath:nil];
}

- (void)startWithGamePath:(NSString * _Nullable)gamePath {
    [[ScummVMAppContext sharedContext] setupIfNeeded];
    [[ScummVMAppContext sharedContext] startWithGamePath:gamePath];
}

- (void)stop {
    [[ScummVMAppContext sharedContext] stop];
}

#if TARGET_OS_IOS || TARGET_OS_TV
- (UIViewController *)ui {
    [[ScummVMAppContext sharedContext] setupIfNeeded];
    return [ScummVMAppContext sharedContext].viewController;
}
#elif TARGET_OS_MAC
- (NSWindow *)ui {
    return [ScummVMAppContext sharedContext].window;
}
#endif

@end

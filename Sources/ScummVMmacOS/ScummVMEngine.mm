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
        [[ScummVMAppContext sharedContext] setupIfNeeded];
    });
    return sharedInstance;
}

@implementation ScummVMEngine

+ (instancetype)sharedInstance {
    return ScummVMEngineSharedInstance();
}

- (void)start {
    [[ScummVMAppContext sharedContext] setupIfNeeded];
    [[ScummVMAppContext sharedContext] start];
}

- (void)stop {
    [[ScummVMAppContext sharedContext] stop];
}

@end

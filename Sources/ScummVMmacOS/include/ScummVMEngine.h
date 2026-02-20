//
//  ScummVMEngine.h
//  ScummVM
//
//  Created by Dominic Opitz on 2/14/25.
//

#import <Foundation/Foundation.h>

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

@end

NS_ASSUME_NONNULL_END

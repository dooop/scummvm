//
//  ScummVMAppContext.h
//  ScummVM
//
//  Created by Dominic Opitz on 3/30/25.
//

#import <Foundation/Foundation.h>

@interface ScummVMAppContext : NSObject

+ (instancetype)sharedContext;
- (void)setupIfNeeded;
- (void)start;
- (void)startWithGamePath:(nullable NSString *)gamePath;
- (void)stop;

@end

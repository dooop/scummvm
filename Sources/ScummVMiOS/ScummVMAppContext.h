//
//  ScummVMAppContext.h
//  ScummVM
//
//  Created by Dominic Opitz on 3/30/25.
//

#import <UIKit/UIKit.h>
#import "backends/platform/ios7/ios7_scummvm_view_controller.h"

@interface ScummVMAppContext : NSObject

@property (nonatomic, strong, readonly)
iOS7ScummVMViewController *viewController;

+ (instancetype)sharedContext;
- (void)setupIfNeeded;
- (void)start;
- (void)startWithGamePath:(nullable NSString *)gamePath;
- (void)stop;

@end

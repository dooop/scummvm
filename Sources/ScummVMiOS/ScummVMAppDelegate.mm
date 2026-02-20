//
//  ScummVMAppDelegate.mm
//  ScummVM
//
//  Created by Dominic Opitz on 3/30/25.
//

#import "ScummVMAppContext.h"
#import "backends/platform/ios7/ios7_app_delegate.h"
#import "backends/platform/ios7/ios7_scummvm_view_controller.h"
#import "backends/platform/ios7/ios7_video.h"

@implementation iOS7AppDelegate {
    iPhoneView *_iPhoneView;
}

+ (instancetype)sharedInstance {
    static iOS7AppDelegate *sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[iOS7AppDelegate alloc] init];
    });
    return sharedInstance;
}

+ (iOS7AppDelegate *)iOS7AppDelegate {
    return [self sharedInstance];
}

+ (iPhoneView *)iPhoneView {
    if ([NSThread currentThread] == [NSThread mainThread]) {
        return (iPhoneView *)[ScummVMAppContext sharedContext].viewController.view;
    } else {
        __block iPhoneView *view = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            view = (iPhoneView *)[ScummVMAppContext sharedContext].viewController.view;
        });
        return view;
    }    
}

#if TARGET_OS_IOS
+ (UIInterfaceOrientation)currentOrientation {
    return [ScummVMAppContext sharedContext].viewController.currentOrientation;
}
#endif

@end

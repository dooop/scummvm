//
//  ScummVMAppContext.mm
//  ScummVM
//
//  Created by Dominic Opitz on 3/30/25.
//

#define FORBIDDEN_SYMBOL_ALLOW_ALL

#include "backends/platform/sdl/macosx/macosx.h"
#include "backends/platform/sdl/macosx/macosx_wrapper.h"
#include "base/main.h"
#include "common/str.h"
#include "common/system.h"

#import "ScummVMAppContext.h"
#import <Foundation/Foundation.h>

static BOOL SCVMArgumentsContainOption(NSArray<NSString *> *arguments, NSString *option) {
    NSString *prefix = [option stringByAppendingString:@"="];
    for (NSString *argument in arguments) {
        if ([argument isEqualToString:option] || [argument hasPrefix:prefix]) {
            return YES;
        }
    }
    return NO;
}

static NSString *SCVMFindAbsoluteDirectoryContainingFile(NSString *fileName) {
    NSString *root = NSBundle.mainBundle.resourcePath;
    if (root.length == 0) {
        return nil;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSDirectoryEnumerator<NSString *> *enumerator = [fileManager enumeratorAtPath:root];
    NSString *relativePath = nil;

    while ((relativePath = [enumerator nextObject])) {
        if (![[relativePath lastPathComponent] isEqualToString:fileName]) {
            continue;
        }

        NSString *absolutePath = [root stringByAppendingPathComponent:relativePath];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:absolutePath isDirectory:&isDirectory] || isDirectory) {
            continue;
        }

        return [absolutePath stringByDeletingLastPathComponent];
    }

    return nil;
}

static NSMutableArray<NSString *> *SCVMBuildRuntimeArguments(void) {
    NSMutableArray<NSString *> *arguments = [NSProcessInfo processInfo].arguments.mutableCopy;

    NSString *themePath = SCVMFindAbsoluteDirectoryContainingFile(@"scummmodern.zip");
    NSString *extraPath = SCVMFindAbsoluteDirectoryContainingFile(@"engine_data_core.mk");

    if (themePath.length > 0 && !SCVMArgumentsContainOption(arguments, @"--themepath")) {
        [arguments addObject:[@"--themepath=" stringByAppendingString:themePath]];
    }

    if (themePath.length > 0 && !SCVMArgumentsContainOption(arguments, @"--iconspath")) {
        [arguments addObject:[@"--iconspath=" stringByAppendingString:themePath]];
    }

    if (extraPath.length > 0 && !SCVMArgumentsContainOption(arguments, @"--extrapath")) {
        [arguments addObject:[@"--extrapath=" stringByAppendingString:extraPath]];
    }

    return arguments;
}

typedef NS_ENUM(NSInteger, SCVMEngineRunState) {
    SCVMEngineRunStateStopped = 0,
    SCVMEngineRunStateStarting = 1,
    SCVMEngineRunStateRunning = 2,
    SCVMEngineRunStateStopping = 3,
};

@implementation ScummVMAppContext {
    BOOL _didSetup;
    SCVMEngineRunState _runState;
}

+ (instancetype)sharedContext {
    static ScummVMAppContext *sharedContext = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedContext = [[ScummVMAppContext alloc] init];
    });
    return sharedContext;
}

- (void)setupIfNeeded {
    @synchronized (self) {
        if (_didSetup) {
            return;
        }
        _didSetup = YES;
    }

    // Create savegames directory
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *documentPath = [NSString stringWithUTF8String:getDocumentsPathMacOSX().c_str()];
    NSString *savePath = [documentPath stringByAppendingPathComponent:@"Savegames"];
    if (![fm fileExistsAtPath:savePath]) {
        [fm createDirectoryAtPath:savePath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // Create the OSystem instance
    g_system = new OSystem_MacOSX();
    assert(g_system);
    g_system->init();
}

- (void)teardownIfNeeded {
    if (g_system) {
        g_system->destroy();
        g_system = nullptr;
    }

    @synchronized (self) {
        _didSetup = NO;
        _runState = SCVMEngineRunStateStopped;
    }
}

- (void)start {
    @synchronized (self) {
        if (_runState != SCVMEngineRunStateStopped) {
            return;
        }
        _runState = SCVMEngineRunStateStarting;
    }

    [self setupIfNeeded];

    BOOL shouldLaunch = NO;
    @synchronized (self) {
        if (_runState == SCVMEngineRunStateStarting) {
            _runState = SCVMEngineRunStateRunning;
            shouldLaunch = YES;
        }
    }
    if (!shouldLaunch) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self teardownIfNeeded];
        });
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<NSString *> *arguments = SCVMBuildRuntimeArguments();
        int argc = (int)arguments.count;
        char **argv = (char **)malloc(sizeof(char *) * (argc + 1));
        for (int i = 0; i < argc; i++) {
            argv[i] = strdup([arguments[i] UTF8String]);
        }
        argv[argc] = NULL;

        scummvm_main(argc, argv);

        for (int i = 0; i < argc; i++) {
            free(argv[i]);
        }
        free(argv);

        [self teardownIfNeeded];
    });
}

- (void)stop {
    SCVMEngineRunState previousState;
    @synchronized (self) {
        previousState = _runState;
        if (_runState == SCVMEngineRunStateStopped || _runState == SCVMEngineRunStateStopping) {
            return;
        }
        _runState = SCVMEngineRunStateStopping;
    }

    if (previousState == SCVMEngineRunStateStarting) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self teardownIfNeeded];
        });
        return;
    }

    if (g_system) {
        g_system->quit();
    }
}

@end

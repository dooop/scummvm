//
//  ScummVMAppContext.mm
//  ScummVM
//
//  Created by Dominic Opitz on 3/30/25.
//

#define FORBIDDEN_SYMBOL_ALLOW_ALL

#include "common/str.h"
#import "ScummVMAppContext.h"
#import <Foundation/Foundation.h>
#import "backends/platform/ios7/ios7_scummvm_view_controller.h"
#import "backends/platform/ios7/ios7_video.h"

void iOS7_init(int argc, char **argv);
void iOS7_destroySharedOSystemInstance();
void iOS7_buildSharedOSystemInstance();
void iOS7_quitEngine();

typedef NS_ENUM(NSInteger, SCVMEngineRunState) {
    SCVMEngineRunStateStopped = 0,
    SCVMEngineRunStateStarting = 1,
    SCVMEngineRunStateRunning = 2,
    SCVMEngineRunStateStopping = 3,
};

static void SCVMUpsertOption(NSMutableArray<NSString *> *arguments, NSString *option, NSString *value) {
    NSString *prefix = [option stringByAppendingString:@"="];
    NSIndexSet *existing = [arguments indexesOfObjectsPassingTest:^BOOL(NSString *obj, NSUInteger idx, BOOL *stop) {
        return [obj isEqualToString:option] || [obj hasPrefix:prefix];
    }];

    if (existing.count > 0) {
        [arguments removeObjectsAtIndexes:existing];
    }

    if (value.length > 0) {
        [arguments addObject:[option stringByAppendingFormat:@"=%@", value]];
    }
}

static BOOL SCVMArgumentsContainValue(NSArray<NSString *> *arguments, NSString *value) {
    for (NSString *argument in arguments) {
        if ([argument isEqualToString:value]) {
            return YES;
        }
    }
    return NO;
}

static NSString *SCVMFindBundleRelativeDirectoryContainingFile(NSString *fileName) {
    NSString *root = NSBundle.mainBundle.resourcePath;
    if (root.length == 0) {
        return nil;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSDirectoryEnumerator<NSString *> *enumerator = [fileManager enumeratorAtPath:root];
    NSString *relativePath = nil;
    NSString *bestDirectory = nil;
    NSUInteger bestDepth = NSUIntegerMax;

    while ((relativePath = [enumerator nextObject])) {
        if (![[relativePath lastPathComponent] isEqualToString:fileName]) {
            continue;
        }

        NSString *absolutePath = [root stringByAppendingPathComponent:relativePath];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:absolutePath isDirectory:&isDirectory] || isDirectory) {
            continue;
        }

        NSString *directory = [relativePath stringByDeletingLastPathComponent];
        NSUInteger depth = (directory.length == 0) ? 0 : [[directory componentsSeparatedByString:@"/"] count];

        if (bestDirectory == nil || depth < bestDepth ||
            (depth == bestDepth && [directory compare:bestDirectory options:NSCaseInsensitiveSearch] == NSOrderedAscending)) {
            bestDirectory = directory;
            bestDepth = depth;
        }
    }

    return bestDirectory;
}

static NSString *SCVMAppBundleVirtualPath(NSString *relativeDirectory) {
    if (relativeDirectory.length == 0) {
        return @"appbundle:/";
    }
    return [@"appbundle:/" stringByAppendingString:relativeDirectory];
}

static NSString *SCVMStandardizedResolvedPath(NSString *path) {
    if (path.length == 0) {
        return @"";
    }

    NSString *resolvedPath = [path stringByResolvingSymlinksInPath];
    return [resolvedPath stringByStandardizingPath];
}

static BOOL SCVMPathRelativeToDirectory(NSString *path, NSString *directory, NSString **relativePath) {
    if (path.length == 0 || directory.length == 0 || ![path hasPrefix:directory]) {
        return NO;
    }

    NSUInteger directoryLength = directory.length;
    if (path.length > directoryLength && [path characterAtIndex:directoryLength] != '/') {
        return NO;
    }

    if (relativePath != nil) {
        NSString *suffix = [path substringFromIndex:directoryLength];
        if (suffix.length == 0) {
            suffix = @"/";
        } else if ([suffix characterAtIndex:0] != '/') {
            suffix = [@"/" stringByAppendingString:suffix];
        }
        *relativePath = suffix;
    }

    return YES;
}

static NSString *SCVMNormalizeLaunchGamePath(NSString * _Nullable gamePath) {
    NSString *trimmedGamePath = [gamePath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedGamePath.length == 0) {
        return trimmedGamePath;
    }

    // The iOS backend uses a chroot filesystem rooted at the app Documents directory.
    // Convert native absolute paths under that root into chroot-relative paths.
    NSString *documentsPath = [NSString stringWithUTF8String:iOS7_getDocumentsDir().c_str()];
    NSString *resolvedGamePath = SCVMStandardizedResolvedPath(trimmedGamePath);
    NSString *resolvedDocumentsPath = SCVMStandardizedResolvedPath(documentsPath);
    NSString *relativePath = nil;

    if (SCVMPathRelativeToDirectory(resolvedGamePath, resolvedDocumentsPath, &relativePath)) {
        return relativePath;
    }

    NSString *bundleResourcePath = NSBundle.mainBundle.resourcePath;
    NSString *resolvedBundleResourcePath = SCVMStandardizedResolvedPath(bundleResourcePath);
    if (SCVMPathRelativeToDirectory(resolvedGamePath, resolvedBundleResourcePath, &relativePath)) {
        return [@"appbundle:" stringByAppendingString:relativePath];
    }

    return trimmedGamePath;
}

static NSMutableArray<NSString *> *SCVMBuildRuntimeArguments(NSString * _Nullable gamePath) {
    NSMutableArray<NSString *> *arguments = [NSProcessInfo processInfo].arguments.mutableCopy;
    NSString *selectedGuiTheme = nil;

    NSString *themeDirectory = SCVMFindBundleRelativeDirectoryContainingFile(@"scummmodern.zip");
    NSString *extraDirectory = SCVMFindBundleRelativeDirectoryContainingFile(@"engine_data_core.mk");

    // Prefer the theme zip colocated with the engine-data payload.
    // This avoids stale duplicate theme zips from nested ".../themes" folders.
    if (extraDirectory.length > 0) {
        NSString *bundleRootDirectory = [extraDirectory stringByDeletingLastPathComponent];
        NSString *root = NSBundle.mainBundle.resourcePath;
        NSString *candidateThemeZip = [[root stringByAppendingPathComponent:bundleRootDirectory] stringByAppendingPathComponent:@"scummmodern.zip"];
        BOOL isDirectory = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidateThemeZip isDirectory:&isDirectory] && !isDirectory) {
            themeDirectory = bundleRootDirectory;
        }
    }

    NSString *themePath = SCVMAppBundleVirtualPath(themeDirectory);
    NSString *extraPath = SCVMAppBundleVirtualPath(extraDirectory);

    if (themeDirectory.length > 0) {
        SCVMUpsertOption(arguments, @"--themepath", themePath);

        NSString *root = NSBundle.mainBundle.resourcePath;
        NSString *absoluteThemeDir = [root stringByAppendingPathComponent:themeDirectory];
        BOOL isDirectory = NO;

        NSString *remasteredZip = [absoluteThemeDir stringByAppendingPathComponent:@"scummremastered.zip"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:remasteredZip isDirectory:&isDirectory] && !isDirectory) {
            NSString *themeZipPath = [themePath stringByAppendingPathComponent:@"scummremastered.zip"];
            SCVMUpsertOption(arguments, @"--gui-theme", themeZipPath);
            selectedGuiTheme = themeZipPath;
        }
    }

    if (extraDirectory.length > 0) {
        SCVMUpsertOption(arguments, @"--extrapath", extraPath);
    }

    NSString *normalizedGamePath = SCVMNormalizeLaunchGamePath(gamePath);
    if (normalizedGamePath.length > 0) {
        SCVMUpsertOption(arguments, @"--path", normalizedGamePath);
        SCVMUpsertOption(arguments, @"--save-slot", nil);
        if (!SCVMArgumentsContainValue(arguments, @"--save-slot")) {
            [arguments addObject:@"--save-slot"];
        }
        if (!SCVMArgumentsContainValue(arguments, @"--auto-detect")) {
            [arguments addObject:@"--auto-detect"];
        }
    } else {
        SCVMUpsertOption(arguments, @"--save-slot", nil);
    }

    if (themePath.length > 0) {
        NSLog(@"[ScummVM] themepath=%@ gui-theme=%@", themePath, selectedGuiTheme ?: @"<unchanged>");
    }

    return arguments;
}

@implementation ScummVMAppContext {
    SCVMEngineRunState _runState;
    BOOL _hasPendingStartRequest;
    NSString *_pendingStartGamePath;
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
    if ([NSThread isMainThread]) {
        if (_viewController) {
            return;
        }

        CGRect screenBounds = [UIScreen mainScreen].bounds;
        iOS7ScummVMViewController *controller = [[iOS7ScummVMViewController alloc] init];
        iPhoneView *scummView = [[iPhoneView alloc] initWithFrame:screenBounds];

        // Create the directory for savegames
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *documentPath = [NSString stringWithUTF8String:iOS7_getDocumentsDir().c_str()];
        NSString *savePath = [documentPath stringByAppendingPathComponent:@"Savegames"];
        if (![fm fileExistsAtPath:savePath]) {
            [fm createDirectoryAtPath:savePath withIntermediateDirectories:YES attributes:nil error:nil];
        }

#if TARGET_OS_IOS
        scummView.multipleTouchEnabled = NO;
#endif
        controller.view = scummView;
        _viewController = controller;
        return;
    }

    dispatch_sync(dispatch_get_main_queue(), ^{
        [self setupIfNeeded];
    });
}

- (UIViewController *)ui {
    return _viewController;
}

- (void)teardownSharedOSystemAndMarkStopped {
    if ([NSThread isMainThread]) {
        BOOL hasPendingStartRequest = NO;
        NSString *pendingStartGamePath = nil;
        iOS7_destroySharedOSystemInstance();
        @synchronized (self) {
            _runState = SCVMEngineRunStateStopped;
            hasPendingStartRequest = _hasPendingStartRequest;
            pendingStartGamePath = [_pendingStartGamePath copy];
            _hasPendingStartRequest = NO;
            _pendingStartGamePath = nil;
        }

        if (hasPendingStartRequest) {
            [self startWithGamePath:pendingStartGamePath];
        }
        return;
    }

    dispatch_sync(dispatch_get_main_queue(), ^{
        [self teardownSharedOSystemAndMarkStopped];
    });
}

- (void)start {
    [self startWithGamePath:nil];
}

- (void)startWithGamePath:(NSString * _Nullable)gamePath {
    NSString *queuedGamePath = [gamePath copy];
    @synchronized (self) {
        if (_runState == SCVMEngineRunStateStopping) {
            _hasPendingStartRequest = YES;
            _pendingStartGamePath = queuedGamePath;
            return;
        }
        if (_runState != SCVMEngineRunStateStopped) {
            return;
        }
        _hasPendingStartRequest = NO;
        _pendingStartGamePath = nil;
        _runState = SCVMEngineRunStateStarting;
    }

    [self setupIfNeeded];

    if ([NSThread isMainThread]) {
        iOS7_buildSharedOSystemInstance();
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            iOS7_buildSharedOSystemInstance();
        });
    }

    BOOL shouldLaunch = NO;
    @synchronized (self) {
        if (_runState == SCVMEngineRunStateStarting) {
            _runState = SCVMEngineRunStateRunning;
            shouldLaunch = YES;
        }
    }
    if (!shouldLaunch) {
        // Startup was canceled after the shared OSystem was built but before the run loop launched.
        // Tear down synchronously so state only returns to "stopped" after native resources are released.
        [self teardownSharedOSystemAndMarkStopped];
        return;
    }

    NSString *launchGamePath = [gamePath copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Invoke the actual ScummVM main entry point:
        NSArray<NSString *> *arguments = SCVMBuildRuntimeArguments(launchGamePath);
        int argc = (int)arguments.count;
        char **argv = (char **)malloc(sizeof(char *) * (argc + 1));
        
        for (int i = 0; i < argc; i++) {
            argv[i] = strdup([arguments[i] UTF8String]);
        }
        argv[argc] = NULL;
        
        iOS7_init(argc, argv);
        
        // Clean-up (free each strdup string after use)
        for (int i = 0; i < argc; i++) {
            free(argv[i]);
        }
        free(argv);

        // Engine has fully exited; destroy the OSystem only now.
        [self teardownSharedOSystemAndMarkStopped];
    });
}

- (void)stop {
    SCVMEngineRunState previousState;
    @synchronized (self) {
        previousState = _runState;
        _hasPendingStartRequest = NO;
        _pendingStartGamePath = nil;
        if (_runState == SCVMEngineRunStateStopped || _runState == SCVMEngineRunStateStopping) {
            return;
        }
        _runState = SCVMEngineRunStateStopping;
    }

    // If startup was canceled before the run loop launched, startWithGamePath: will perform teardown
    // and transition the state back to stopped once native resources are released.
    if (previousState == SCVMEngineRunStateStarting) {
        return;
    }

    // Signal the engine loop to exit. Teardown happens in the start() worker after iOS7_init returns.
    iOS7_quitEngine();
}

@end

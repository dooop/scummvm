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
#include "common/path.h"
#include "common/str.h"
#include "common/system.h"
#include "common/translation.h"
#include "engines/engine.h"
#include "engines/metaengine.h"

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

static BOOL SCVMArgumentsContainValue(NSArray<NSString *> *arguments, NSString *value) {
    for (NSString *argument in arguments) {
        if ([argument isEqualToString:value]) {
            return YES;
        }
    }
    return NO;
}

static void SCVMRemoveValue(NSMutableArray<NSString *> *arguments, NSString *value) {
    NSIndexSet *existing = [arguments indexesOfObjectsPassingTest:^BOOL(NSString *obj, NSUInteger idx, BOOL *stop) {
        return [obj isEqualToString:value];
    }];

    if (existing.count > 0) {
        [arguments removeObjectsAtIndexes:existing];
    }
}

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

static void SCVMClearPersistedSaveSlotHints() {
    bool didChange = false;
    for (Common::ConfigManager::DomainMap::iterator iter = ConfMan.beginGameDomains(); iter != ConfMan.endGameDomains(); ++iter) {
        Common::String targetName(iter->_key);
        if (ConfMan.hasKey("save_slot", targetName)) {
            ConfMan.removeKey("save_slot", targetName);
            didChange = true;
        }
    }

    if (didChange) {
        ConfMan.flushToDisk();
    }
}

static void SCVMPersistSaveSlotHintForActiveTarget(int saveSlot) {
    if (saveSlot < 0) {
        return;
    }

    Common::String targetName = ConfMan.getActiveDomainName();
    if (targetName.empty()) {
        return;
    }

    ConfMan.setInt("save_slot", saveSlot, targetName);
    ConfMan.flushToDisk();
}

static NSString *SCVMStandardizedResolvedPath(NSString *path) {
    if (path.length == 0) {
        return @"";
    }

    NSString *resolvedPath = [path stringByResolvingSymlinksInPath];
    return [resolvedPath stringByStandardizingPath];
}

static NSString *SCVMFindConfiguredTargetForGamePath(NSString *gamePath) {
    NSString *normalizedInputPath = SCVMStandardizedResolvedPath(gamePath);
    if (normalizedInputPath.length == 0) {
        return nil;
    }

    for (Common::ConfigManager::DomainMap::iterator iter = ConfMan.beginGameDomains(); iter != ConfMan.endGameDomains(); ++iter) {
        Common::String targetName(iter->_key);
        Common::ConfigManager::Domain &domain = iter->_value;
        if (!domain.contains("path")) {
            continue;
        }

        Common::Path configPath = Common::Path::fromConfig(domain.getVal("path"));
        Common::String configPathNative = configPath.toString(Common::Path::kNativeSeparator);
        NSString *configuredPath = [NSString stringWithUTF8String:configPathNative.c_str()];
        NSString *normalizedConfiguredPath = SCVMStandardizedResolvedPath(configuredPath);
        if (![normalizedConfiguredPath isEqualToString:normalizedInputPath]) {
            continue;
        }

        return [NSString stringWithUTF8String:targetName.c_str()];
    }

    return nil;
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

static NSMutableArray<NSString *> *SCVMBuildRuntimeArguments(NSString * _Nullable gamePath) {
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

    NSString *trimmedGamePath = [gamePath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (trimmedGamePath.length > 0) {
        SCVMUpsertOption(arguments, @"--save-slot", nil);
        if (!SCVMArgumentsContainValue(arguments, @"--save-slot")) {
            [arguments addObject:@"--save-slot"];
        }

        NSString *configuredTarget = SCVMFindConfiguredTargetForGamePath(trimmedGamePath);

        if (configuredTarget.length > 0) {
            SCVMUpsertOption(arguments, @"--path", nil);
            SCVMRemoveValue(arguments, @"--auto-detect");
            if (!SCVMArgumentsContainValue(arguments, configuredTarget)) {
                [arguments addObject:configuredTarget];
            }
        } else {
            SCVMUpsertOption(arguments, @"--path", trimmedGamePath);
            if (!SCVMArgumentsContainValue(arguments, @"--auto-detect")) {
                [arguments addObject:@"--auto-detect"];
            }
        }
    } else {
        SCVMUpsertOption(arguments, @"--save-slot", nil);
        SCVMClearPersistedSaveSlotHints();
    }

    return arguments;
}

typedef NS_ENUM(NSInteger, SCVMEngineRunState) {
    SCVMEngineRunStateStopped = 0,
    SCVMEngineRunStateStarting = 1,
    SCVMEngineRunStateRunning = 2,
    SCVMEngineRunStateStopping = 3,
};

static void SCVMPerformBestEffortAutosaveBeforeQuit() {
    if (!g_engine) {
        return;
    }

    int autosaveSlot = g_engine->getAutosaveSlot();
    if (autosaveSlot < 0) {
        return;
    }

    if (g_engine->saveGameState(autosaveSlot, _("Autosave"), true).getCode() == Common::kNoError) {
        SCVMPersistSaveSlotHintForActiveTarget(autosaveSlot);
    }
}

// ---------------------------------------------------------------------------
// Wrapper-level autosave timer
//
// On macOS, scummvm_main blocks the main thread. The SwiftUI stop() callback
// cannot execute until after the engine has already exited and g_engine is nil.
// To work around this, we schedule an NSTimer on the main run loop that fires
// periodically during SDL's event processing (SDL pumps the NSApplication
// event loop, which triggers run-loop timers). This mirrors how the iOS
// override performs saveState() from within the engine's event handling.
// ---------------------------------------------------------------------------

static NSTimer *g_scummVMWrapperAutosaveTimer = nil;
static NSString *g_scummVMLastKnownActiveTarget = nil;
static BOOL g_scummVMTimerDidPersistHint = NO;

static void SCVMStopWrapperAutosaveTimer() {
    if (g_scummVMWrapperAutosaveTimer) {
        [g_scummVMWrapperAutosaveTimer invalidate];
        g_scummVMWrapperAutosaveTimer = nil;
    }
}

static void SCVMWrapperAutosaveTick() {
    if (!g_engine) {
        return;
    }

    // Track the active target so we can persist the hint after scummvm_main returns
    // (at which point the active domain has been cleared).
    Common::String activeName = ConfMan.getActiveDomainName();
    if (!activeName.empty()) {
        g_scummVMLastKnownActiveTarget = [NSString stringWithUTF8String:activeName.c_str()];
    }

    if (!g_engine->hasFeature(Engine::kSupportsSavingDuringRuntime) ||
        !g_engine->canSaveAutosaveCurrently()) {
        return;
    }

    if (!g_engine->getMetaEngine()->hasFeature(MetaEngine::kSupportsLoadingDuringStartup)) {
        return;
    }

    int autosaveSlot = g_engine->getAutosaveSlot();
    if (autosaveSlot < 0) {
        return;
    }

    // Avoid overwriting a manual user save that happens to occupy the autosave slot.
    Common::String targetName(ConfMan.getActiveDomainName());
    SaveStateDescriptor desc = g_engine->getMetaEngine()->querySaveMetaInfos(targetName.c_str(), autosaveSlot);
    if (desc.getSaveSlot() != -1 && !desc.isAutosave()) {
        return;
    }

    Common::Error saveErr = g_engine->saveGameState(autosaveSlot, _("Autosave"), true);
    if (saveErr.getCode() == Common::kNoError) {
        SCVMPersistSaveSlotHintForActiveTarget(autosaveSlot);
        g_scummVMTimerDidPersistHint = YES;
    }
}

static void SCVMStartWrapperAutosaveTimer() {
    SCVMStopWrapperAutosaveTimer();
    g_scummVMLastKnownActiveTarget = nil;
    g_scummVMTimerDidPersistHint = NO;

    // Use a short initial delay (5s) so that even brief sessions get an autosave.
    // After the first tick, reschedule at a 30s interval.
    g_scummVMWrapperAutosaveTimer = [NSTimer timerWithTimeInterval:5.0
                                                           repeats:NO
                                                             block:^(NSTimer * _Nonnull timer) {
        SCVMWrapperAutosaveTick();

        // Reschedule as a repeating timer at the normal interval.
        SCVMStopWrapperAutosaveTimer();
        g_scummVMWrapperAutosaveTimer = [NSTimer timerWithTimeInterval:30.0
                                                               repeats:YES
                                                                 block:^(NSTimer * _Nonnull repeatingTimer) {
            SCVMWrapperAutosaveTick();
        }];
        [[NSRunLoop mainRunLoop] addTimer:g_scummVMWrapperAutosaveTimer forMode:NSRunLoopCommonModes];
    }];
    [[NSRunLoop mainRunLoop] addTimer:g_scummVMWrapperAutosaveTimer forMode:NSRunLoopCommonModes];
}

// After scummvm_main returns, check whether the timer already persisted the save_slot hint.
// If it did, the hint is already flushed to disk and no further action is needed.
// If it didn't, we cannot safely write to ConfMan because the auto-detected game domain may
// have been removed during the engine's normal cleanup.
static void SCVMPersistSaveSlotHintAfterEngineExit(NSString *launchGamePath) {
    g_scummVMLastKnownActiveTarget = nil;
    g_scummVMTimerDidPersistHint = NO;
}

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
    [self startWithGamePath:nil];
}

- (void)startWithGamePath:(NSString * _Nullable)gamePath {
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

    NSString *launchGamePath = [gamePath copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<NSString *> *arguments = SCVMBuildRuntimeArguments(launchGamePath);
        int argc = (int)arguments.count;
        char **argv = (char **)malloc(sizeof(char *) * (argc + 1));
        for (int i = 0; i < argc; i++) {
            argv[i] = strdup([arguments[i] UTF8String]);
        }
        argv[argc] = NULL;

        SCVMStartWrapperAutosaveTimer();
        scummvm_main(argc, argv);
        SCVMStopWrapperAutosaveTimer();

        SCVMPersistSaveSlotHintAfterEngineExit(launchGamePath);

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
        SCVMPerformBestEffortAutosaveBeforeQuit();
        g_system->quit();
    }
}

@end

#define FORBIDDEN_SYMBOL_ALLOW_ALL

#include <assert.h>
#include <atomic>
#include <stdio.h>
#include <unistd.h>

#include "backends/platform/ios7/ios7_osys_main.h"
#include "base/main.h"
#include "common/config-manager.h"
#include "common/events.h"
#include "common/translation.h"
#include "common/system.h"
#include "engines/engine.h"
#include "engines/metaengine.h"

extern std::atomic<bool> g_scummVMIOSWrapperTimerCallbacksEnabled;

static void iOS7_performBestEffortAutosaveBeforeQuit() {
	if (!g_engine)
		return;

	if (!g_engine->hasFeature(Engine::kSupportsSavingDuringRuntime) || !g_engine->canSaveAutosaveCurrently())
		return;

	MetaEngine *metaEngine = g_engine->getMetaEngine();
	if (!metaEngine || !metaEngine->hasFeature(MetaEngine::kSupportsLoadingDuringStartup))
		return;

	const Common::String targetName(ConfMan.getActiveDomainName());
	const int autosaveSlot = g_engine->getAutosaveSlot();
	if (autosaveSlot < 0)
		return;

	const SaveStateDescriptor descriptor = metaEngine->querySaveMetaInfos(targetName.c_str(), autosaveSlot);
	if (descriptor.getSaveSlot() != -1 && !descriptor.isAutosave())
		return;

	g_engine->saveGameState(autosaveSlot, _("Autosave"), true);
}

void iOS7_destroySharedOSystemInstance() {
	if (g_system) {
		g_scummVMIOSWrapperTimerCallbacksEnabled.store(false, std::memory_order_relaxed);
		g_system->destroy();
		g_system = nullptr;
	}
}

void iOS7_quitEngine() {
	if (g_system) {
		// Embedded stop requests must not be redirected into the launcher.
		ConfMan.setBool("gui_return_to_launcher_at_exit", false, Common::ConfigManager::kTransientDomain);
		ConfMan.setBool("confirm_exit", false, Common::ConfigManager::kTransientDomain);

		iOS7_performBestEffortAutosaveBeforeQuit();

		if (g_system->getEventManager()) {
			g_system->getEventManager()->resetReturnToLauncher();
			g_system->getEventManager()->resetQuit();
		}

		if (g_engine) {
			// Many engine loops check Engine::shouldQuit() and honor the internal
			// _quitRequested flag even before backend events are processed.
			Engine::quitGame();
		}

		g_system->quit();
	}
}

void iOS7_init(int argc, char **argv) {
	Common::String logFilePath = iOS7_getDocumentsDir() + "/scummvm.log";
	FILE *logFile = isatty(STDERR_FILENO) != 1 ? fopen(logFilePath.c_str(), "a") : nullptr;

	if (logFile != nullptr) {
		long sz = ftell(logFile);
		if (sz > MAX_IOS7_SCUMMVM_LOG_FILESIZE_IN_BYTES) {
			fclose(logFile);
			fprintf(stdout, "Default log file is bigger than %dKB. It will be overwritten!", MAX_IOS7_SCUMMVM_LOG_FILESIZE_IN_BYTES / 1024);
			logFile = fopen(logFilePath.c_str(), "w");
			if (logFile == nullptr)
				fprintf(stdout, "Could not open default log file for rewrite!");
		}
		if (logFile != nullptr) {
			fclose(stdout);
			fclose(stderr);
			*stdout = *logFile;
			*stderr = *logFile;
			setbuf(stdout, nullptr);
			setbuf(stderr, nullptr);
		}
	}

	chdir(iOS7_getDocumentsDir().c_str());

	g_system = OSystem_iOS7::sharedInstance();
	if (!g_system) {
		fprintf(stderr, "Failed to create OSystem_iOS7 shared instance\n");
		return;
	}

	scummvm_main(argc, (const char *const *)argv);

	if (logFile != nullptr)
		fclose(logFile);
}

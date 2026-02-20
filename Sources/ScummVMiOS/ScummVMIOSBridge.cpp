#define FORBIDDEN_SYMBOL_ALLOW_ALL

#include <assert.h>
#include <stdio.h>
#include <unistd.h>

#include "backends/platform/ios7/ios7_osys_main.h"
#include "base/main.h"
#include "common/system.h"

void iOS7_destroySharedOSystemInstance() {
	if (g_system) {
		g_system->destroy();
		g_system = nullptr;
	}
}

void iOS7_quitEngine() {
	if (g_system) {
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

SHELL := /bin/bash

.PHONY: sdk build debug release clean logs rebuild alwaysclean

sdk:
	bash scripts/setup-android-sdk.sh && source $$HOME/.bashrc

build: debug

debug:
	./gradlew assembleDebug

release:
	./gradlew assembleRelease

clean:
	./gradlew clean

# Capture focused crash logs for the app (requires adb/platform-tools)
logs:
	bash scripts/capture-crash-log.sh

# Clean + assemble to ensure memory and outputs are fresh
rebuild:
	./gradlew clean assembleDebug

# Alias to enforce clean-first debug builds
alwaysclean: rebuild

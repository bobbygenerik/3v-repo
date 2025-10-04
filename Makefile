SHELL := /bin/bash

.PHONY: sdk build debug release clean

sdk:
	bash scripts/setup-android-sdk.sh && source $$HOME/.bashrc

build: debug

debug:
	./gradlew assembleDebug

release:
	./gradlew assembleRelease

clean:
	./gradlew clean

APP_NAME    := Claude Profiles
EXECUTABLE  := ClaudeProfiles
BUILD_DIR   := build
APP         := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications
VERSION     ?= $(shell tag=$$(git describe --tags --abbrev=0 2>/dev/null); echo "$${tag:-v0.0.0}" | sed 's/^v//')
BUILD       ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
ARCHS       := --arch arm64 --arch x86_64

.PHONY: all build test app install run screenshots icon release clean

all: app

## Debug build of the package (fast; used while developing)
build:
	swift build

## Unit tests for the core module
test:
	swift test

## Universal release build bundled as a .app, ad-hoc signed
app:
	swift build -c release $(ARCHS)
	$(eval BIN_DIR := $(shell swift build -c release $(ARCHS) --show-bin-path))
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN_DIR)/$(EXECUTABLE)" "$(APP)/Contents/MacOS/$(EXECUTABLE)"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	sed -e 's/__VERSION__/$(VERSION)/' -e 's/__BUILD__/$(BUILD)/' Resources/Info.plist > "$(APP)/Contents/Info.plist"
	codesign --force --sign - --identifier dev.mutesacedric.claude-profiles "$(APP)"
	@echo "Built $(APP) (v$(VERSION), build $(BUILD))"

## Copy the app to ~/Applications and (re)launch it
install: app
	mkdir -p "$(INSTALL_DIR)"
	-pkill -x $(EXECUTABLE)
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

## Build and launch from the build folder
run: app
	-pkill -x $(EXECUTABLE)
	open "$(APP)"

## Regenerate the README screenshots from the real UI with demo data
screenshots: app
	"$(APP)/Contents/MacOS/$(EXECUTABLE)" --capture docs/screenshots

## Regenerate the app icon from Scripts/make-icon.swift
icon:
	swift Scripts/make-icon.swift Resources/AppIcon.icns docs/icon.png

## Zip the app for a GitHub release
release: app
	rm -f "$(BUILD_DIR)/$(APP_NAME).zip"
	ditto -c -k --keepParent "$(APP)" "$(BUILD_DIR)/$(APP_NAME).zip"
	@echo "Wrote $(BUILD_DIR)/$(APP_NAME).zip"

clean:
	rm -rf .build "$(BUILD_DIR)"

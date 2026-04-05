.PHONY: build run install clean

APP_NAME = XMURollcall
BUILD_DIR = .build
INSTALL_DIR = /Applications

build:
	swift build -c release
	mkdir -p $(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS
	mkdir -p $(BUILD_DIR)/$(APP_NAME).app/Contents/Resources
	cp $(BUILD_DIR)/release/$(APP_NAME) $(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/
	cp -r Sources/XMURollcall/Resources/python_scripts $(BUILD_DIR)/$(APP_NAME).app/Contents/Resources/
	# Create Info.plist
	@rm -f $(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $(APP_NAME)" $(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.xmu.rollcall" $(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleName string $(APP_NAME)" $(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" $(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1.0.0" $(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" $(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 26.0" $(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" $(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" $(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist
	# Ad-hoc sign
	codesign --force --sign - $(BUILD_DIR)/$(APP_NAME).app

run: build
	open $(BUILD_DIR)/$(APP_NAME).app

install: build
	cp -r $(BUILD_DIR)/$(APP_NAME).app $(INSTALL_DIR)/

clean:
	swift package clean
	rm -rf $(BUILD_DIR)/$(APP_NAME).app

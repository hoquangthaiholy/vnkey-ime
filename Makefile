# Makefile for VnKey Vietnamese Input Method on macOS

APP_NAME = VnKey
BUILD_DIR = .build
BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR = $(BUNDLE)/Contents/MacOS
RESOURCES_DIR = $(BUNDLE)/Contents/Resources
INSTALL_DIR = $(HOME)/Library/Input\ Methods

SOURCES = Sources/CharsetConverter.swift Sources/Preferences.swift Sources/VnEngine.swift Sources/Autocomplete.swift Sources/AppDelegate.swift Sources/StatusMenuController.swift Sources/VnInputController.swift Sources/main.swift

.PHONY: all clean install reload uninstall

all: $(BUNDLE)

$(BUNDLE): $(SOURCES) Sources/Viet11K.txt Sources/Info.plist
	@echo "Compiling Swift files..."
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	swiftc -Osize -Xlinker -dead_strip $(SOURCES) -o $(MACOS_DIR)/$(APP_NAME)
	@echo "Copying Info.plist and resources..."
	@cp Sources/Info.plist $(BUNDLE)/Contents/Info.plist
	@cp Sources/Viet11K.txt $(RESOURCES_DIR)/Viet11K.txt
	@cp Sources/Assets/IMEMenuIcon.png $(RESOURCES_DIR)/IMEMenuIcon.png
	@cp Sources/Assets/IMEMenuIcon@2x.png $(RESOURCES_DIR)/IMEMenuIcon@2x.png
		@mkdir -p $(RESOURCES_DIR)/en.lproj
	@mkdir -p $(RESOURCES_DIR)/vi.lproj
	@cp Sources/en.lproj/InfoPlist.strings $(RESOURCES_DIR)/en.lproj/InfoPlist.strings
	@cp Sources/vi.lproj/InfoPlist.strings $(RESOURCES_DIR)/vi.lproj/InfoPlist.strings
	@echo "Stripping binary..."
	strip $(MACOS_DIR)/$(APP_NAME)
	@echo "Signing the bundle..."
	codesign -f -s - $(BUNDLE)
	@echo "Build successful: $(BUNDLE)"

install: all
	@echo "Installing to $(INSTALL_DIR)..."
	@mkdir -p $(INSTALL_DIR)
	@rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(BUNDLE) $(INSTALL_DIR)/
	@echo "Registering input source by launching the app..."
	@# Launch the app once to trigger TISRegisterInputSource
	@open $(INSTALL_DIR)/$(APP_NAME).app
	killall -9 TextInputMenuAgent
	killall -9 TextInputSwitcher
	@echo "Installation complete!"
	@echo "Please restart active applications or log out/log in if the input source does not show up immediately."
	@echo "You can enable VnKey in System Settings > Keyboard > Input Sources > +."

reload:
	@echo "Reloading input source..."
	-killall -9 $(APP_NAME) 2>/dev/null || true
	@open $(INSTALL_DIR)/$(APP_NAME).app
	@echo "Input source reloaded!"

uninstall:
	@echo "Uninstalling $(APP_NAME)..."
	-killall -9 $(APP_NAME) 2>/dev/null || true
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	@echo "Refreshing input services..."
	@touch $(INSTALL_DIR)
	-killall -9 TextInputMenuAgent 2>/dev/null || true
	-killall -9 TextInputSwitcher 2>/dev/null || true
	@echo "VnKey has been successfully uninstalled."

clean:
	rm -rf $(BUILD_DIR)

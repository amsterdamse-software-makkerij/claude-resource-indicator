CONFIG    ?= release
BINNAME   := ClaudeResourceIndicator
APPNAME   := Claude Resource Indicator
BUNDLE    := build/$(APPNAME).app
BUILT_BIN := $(shell swift build -c $(CONFIG) --show-bin-path)/$(BINNAME)

.PHONY: build app run install selftest icon universal dist dmg clean

build:
	swift build -c $(CONFIG)

icon:
	swift Tools/MakeIcon.swift Resources/AppIcon.icns

app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(BUILT_BIN)" "$(BUNDLE)/Contents/MacOS/$(BINNAME)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"; fi
	xattr -cr "$(BUNDLE)"
	codesign --force --sign - "$(BUNDLE)"
	@echo "Built $(BUNDLE)"

universal:
	swift build -c $(CONFIG) --arch arm64
	swift build -c $(CONFIG) --arch x86_64
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	lipo -create "$$(swift build -c $(CONFIG) --arch arm64 --show-bin-path)/$(BINNAME)" "$$(swift build -c $(CONFIG) --arch x86_64 --show-bin-path)/$(BINNAME)" -output "$(BUNDLE)/Contents/MacOS/$(BINNAME)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"; fi
	xattr -cr "$(BUNDLE)"
	codesign --force --sign - "$(BUNDLE)"
	@echo "Built universal $(BUNDLE)"
	@lipo -archs "$(BUNDLE)/Contents/MacOS/$(BINNAME)"

dist: universal
	cd build && ditto -c -k --keepParent "$(APPNAME).app" "ClaudeResourceIndicator.zip"
	@echo "Packaged -> build/ClaudeResourceIndicator.zip"

dmg: universal
	rm -rf build/dmg "build/$(BINNAME).dmg"
	mkdir -p build/dmg
	cp -R "$(BUNDLE)" "build/dmg/$(APPNAME).app"
	ln -s /Applications "build/dmg/Applications"
	hdiutil create -volname "$(APPNAME)" -srcfolder build/dmg -ov -format UDZO "build/$(BINNAME).dmg"
	rm -rf build/dmg
	@echo "Packaged -> build/$(BINNAME).dmg"

run: app
	open "$(BUNDLE)"

install: app
	rm -rf "/Applications/$(APPNAME).app"
	cp -R "$(BUNDLE)" "/Applications/$(APPNAME).app"
	@echo "Installed to /Applications/$(APPNAME).app"

selftest: build
	"$(BUILT_BIN)" --selftest

clean:
	swift package clean
	rm -rf build

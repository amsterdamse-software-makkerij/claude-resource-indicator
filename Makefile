CONFIG    ?= release
BINNAME   := ClaudeResourceIndicator
APPNAME   := Claude Resource Indicator
BUNDLE    := build/$(APPNAME).app
ENTITLEMENTS := Resources/Entitlements.plist

# Signing identity for `app`/`universal`/`dmg`. Defaults to ad-hoc ("-") for local
# dev; `sign`/`release` require a real Developer ID (B2).
SIGNING_IDENTITY ?= -

# Deferred (=) so `swift build --show-bin-path` only runs when a recipe actually
# needs the path — not on every make invocation, and not before the build (B3).
BUILT_BIN  = $(shell swift build -c $(CONFIG) --show-bin-path)/$(BINNAME)
ARM64_BIN  = $(shell swift build -c $(CONFIG) --arch arm64 --show-bin-path)/$(BINNAME)
X86_64_BIN = $(shell swift build -c $(CONFIG) --arch x86_64 --show-bin-path)/$(BINNAME)

LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

.PHONY: build app run install selftest test icon universal dist dmg package-dmg sign notarize release clean

build:
	swift build -c $(CONFIG)

test:
	swift test

icon:
	swift Tools/MakeIcon.swift Resources/AppIcon.icns

app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(BUILT_BIN)" "$(BUNDLE)/Contents/MacOS/$(BINNAME)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	plutil -replace CFBundleExecutable -string "$(BINNAME)" "$(BUNDLE)/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"; fi
	xattr -cr "$(BUNDLE)"
	codesign --force --sign "$(SIGNING_IDENTITY)" "$(BUNDLE)"
	codesign --verify --deep --strict "$(BUNDLE)"
	@touch "$(BUNDLE)"; "$(LSREGISTER)" -f "$(BUNDLE)" 2>/dev/null || true
	@echo "Built $(BUNDLE)"

universal:
	swift build -c $(CONFIG) --arch arm64
	swift build -c $(CONFIG) --arch x86_64
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	lipo -create "$(ARM64_BIN)" "$(X86_64_BIN)" -output "$(BUNDLE)/Contents/MacOS/$(BINNAME)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	plutil -replace CFBundleExecutable -string "$(BINNAME)" "$(BUNDLE)/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"; fi
	xattr -cr "$(BUNDLE)"
	codesign --force --sign "$(SIGNING_IDENTITY)" "$(BUNDLE)"
	codesign --verify --deep --strict "$(BUNDLE)"
	@touch "$(BUNDLE)"; "$(LSREGISTER)" -f "$(BUNDLE)" 2>/dev/null || true
	@echo "Built universal $(BUNDLE)"
	@lipo -archs "$(BUNDLE)/Contents/MacOS/$(BINNAME)"

dist: universal
	cd build && ditto -c -k --keepParent "$(APPNAME).app" "ClaudeResourceIndicator.zip"
	@echo "Packaged -> build/ClaudeResourceIndicator.zip"

# Package the already-built bundle into a DMG without rebuilding — so the release
# chain can sign the .app first and not have it clobbered by another build.
package-dmg:
	rm -rf build/dmg "build/$(BINNAME).dmg"
	mkdir -p build/dmg
	cp -R "$(BUNDLE)" "build/dmg/$(APPNAME).app"
	ln -s /Applications "build/dmg/Applications"
	hdiutil create -volname "$(APPNAME)" -srcfolder build/dmg -ov -format UDZO "build/$(BINNAME).dmg"
	rm -rf build/dmg
	@echo "Packaged -> build/$(BINNAME).dmg"

dmg: universal package-dmg

run: app
	open "$(BUNDLE)"

install: app
	rm -rf "/Applications/$(APPNAME).app"
	cp -R "$(BUNDLE)" "/Applications/$(APPNAME).app"
	@echo "Installed to /Applications/$(APPNAME).app"

# Diagnostics are #if DEBUG only (B1), so run against a debug build.
selftest:
	swift build
	"$(shell swift build --show-bin-path)/$(BINNAME)" --selftest

# --- Distribution: Developer ID signing + notarization (B2) -------------------
# Requires a real Developer ID. See docs/superpowers/specs/2026-06-14-*.md for the
# full release pipeline (CI workflow, Homebrew tap) this plumbing feeds.

sign:
	@if [ "$(SIGNING_IDENTITY)" = "-" ]; then \
		echo "error: set SIGNING_IDENTITY to a Developer ID Application identity (currently ad-hoc '-')"; exit 1; fi
	codesign --force --deep --options runtime --timestamp \
		--entitlements "$(ENTITLEMENTS)" \
		--sign "$(SIGNING_IDENTITY)" "$(BUNDLE)"
	codesign --verify --deep --strict "$(BUNDLE)"

notarize:
	@[ -n "$(AC_API_KEY_ID)" ]        || { echo "error: AC_API_KEY_ID unset"; exit 1; }
	@[ -n "$(AC_API_KEY_ISSUER_ID)" ] || { echo "error: AC_API_KEY_ISSUER_ID unset"; exit 1; }
	@[ -n "$(AC_API_KEY_PATH)" ]      || { echo "error: AC_API_KEY_PATH unset"; exit 1; }
	xcrun notarytool submit "build/$(BINNAME).dmg" \
		--key "$(AC_API_KEY_PATH)" --key-id "$(AC_API_KEY_ID)" --issuer "$(AC_API_KEY_ISSUER_ID)" --wait
	xcrun stapler staple "$(BUNDLE)"
	xcrun stapler staple "build/$(BINNAME).dmg"

# universal -> sign .app (Developer ID + hardened runtime) -> dmg -> sign dmg ->
# notarize + staple both -> Gatekeeper assertion. Fails loudly if any step fails.
release:
	@if [ "$(SIGNING_IDENTITY)" = "-" ]; then \
		echo "error: set SIGNING_IDENTITY to a Developer ID Application identity (currently ad-hoc '-')"; exit 1; fi
	$(MAKE) universal
	$(MAKE) sign
	$(MAKE) package-dmg
	codesign --force --sign "$(SIGNING_IDENTITY)" "build/$(BINNAME).dmg"
	$(MAKE) notarize
	spctl -a -t exec -vv "$(BUNDLE)"
	@echo "Notarized release -> build/$(BINNAME).dmg"

clean:
	swift package clean
	rm -rf build

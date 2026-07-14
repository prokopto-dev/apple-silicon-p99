# Builds "P99 Installer.app" — the GUI front end for the scripts in scripts/.
# Needs only Apple's Command Line Tools (swift + sips/iconutil), not Xcode.
#
#   make            same as `make app`
#   make app        build dist/P99 Installer.app (ad-hoc signed, runs locally)
#   make test       Swift unit tests (swift run p99tests) + script-layer tests
#   make zip        dist/P99-Installer.zip for distribution
#   make icon       regenerate AppIcon.icns from app/Resources/icon-1024.png
#   make notarize   Developer-ID sign + notarize (needs DEVELOPER_ID + NOTARY_PROFILE)
#   make clean

APP_NAME  := P99 Installer
DIST      := dist
APP       := $(DIST)/$(APP_NAME).app
BINARY    := app/.build/release/P99Installer
ICONSET   := $(DIST)/AppIcon.iconset

.PHONY: app test zip icon notarize clean

test:
	swift run -c release --package-path app p99tests
	./scripts/tests.sh

app:
	swift build -c release --package-path app
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BINARY)" "$(APP)/Contents/MacOS/P99Installer"
	cp app/Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp app/Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	# The scripts stay the source of truth in scripts/; each build bundles a
	# fresh copy so the .app is fully self-contained.
	cp -R scripts "$(APP)/Contents/Resources/scripts"
	codesign --force --deep --sign - "$(APP)"
	@echo "Built: $(APP)  (unsigned build — first open needs right-click -> Open)"

zip: app
	ditto -c -k --keepParent "$(APP)" "$(DIST)/P99-Installer.zip"
	@echo "Built: $(DIST)/P99-Installer.zip"

icon:
	rm -rf "$(ICONSET)"; mkdir -p "$(ICONSET)"
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s app/Resources/icon-1024.png --out "$(ICONSET)/icon_$${s}x$${s}.png" >/dev/null; \
	  d=$$((s*2)); \
	  sips -z $$d $$d app/Resources/icon-1024.png --out "$(ICONSET)/icon_$${s}x$${s}@2x.png" >/dev/null; \
	done
	iconutil -c icns "$(ICONSET)" -o app/Resources/AppIcon.icns
	rm -rf "$(ICONSET)"
	@echo "Rebuilt app/Resources/AppIcon.icns"

# Real signing + notarization, for when a $$99/yr Apple Developer ID exists.
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=p99mac make notarize
# (NOTARY_PROFILE is a keychain profile created once with:
#   xcrun notarytool store-credentials p99mac --apple-id you@example.com --team-id TEAMID)
notarize: app
	@test -n "$(DEVELOPER_ID)" || { echo "ERROR: set DEVELOPER_ID (see Makefile comment)"; exit 1; }
	@test -n "$(NOTARY_PROFILE)" || { echo "ERROR: set NOTARY_PROFILE (see Makefile comment)"; exit 1; }
	codesign --force --options runtime --timestamp --sign "$(DEVELOPER_ID)" "$(APP)"
	ditto -c -k --keepParent "$(APP)" "$(DIST)/P99-Installer.zip"
	xcrun notarytool submit "$(DIST)/P99-Installer.zip" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP)"
	ditto -c -k --keepParent "$(APP)" "$(DIST)/P99-Installer.zip"
	@echo "Notarized: $(APP)"

clean:
	rm -rf "$(DIST)" app/.build

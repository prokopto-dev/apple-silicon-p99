# Builds "P99 Installer.app" — the GUI front end for the scripts in scripts/.
# Needs only Apple's Command Line Tools (swift + sips/iconutil), not Xcode.
#
#   make            same as `make app`
#   make app        build dist/P99 Installer.app (ad-hoc signed, runs locally)
#   make beta       build dist/P99 FEX Beta.app (separate experimental channel)
#   make test       Swift unit tests (swift run p99tests) + script-layer tests
#   make coverage   test coverage report for P99Core (llvm-cov, ships with CLT)
#   make zip        dist/P99-Installer.zip for distribution
#   make icon       regenerate AppIcon.icns from app/Resources/icon-1024.png
#   make release V=0.2.0   cut a release: stamp CHANGELOG, commit, tag, push
#   make notarize   Developer-ID sign + notarize (needs DEVELOPER_ID + NOTARY_PROFILE)
#   make clean

APP_NAME  := P99 Installer
# App version = newest released section in CHANGELOG.md; stamped into the
# bundle so the in-app update checker knows what it's running.
VERSION   := $(shell awk -F'[][]' '/^\#\# \[[0-9]/{print $$2; exit}' CHANGELOG.md)
DIST      := dist
APP       := $(DIST)/$(APP_NAME).app
BETA_NAME := P99 FEX Beta
BETA_APP  := $(DIST)/$(BETA_NAME).app
BETA_ZIP  := $(DIST)/P99-FEX-Beta.zip
BINARY    := app/.build/release/P99Installer
ICONSET   := $(DIST)/AppIcon.iconset

.PHONY: app beta beta-zip test coverage zip icon release notarize clean

# Cut a release: verify tests pass and CHANGELOG's [Unreleased] section has
# content, stamp it as [$(V)] with today's date, commit, tag v$(V), push.
# CI then builds and publishes the GitHub Release using that section as notes.
release:
	@test -n "$(V)" || { echo "usage: make release V=0.2.0"; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "ERROR: uncommitted changes — commit or stash first"; exit 1; }
	@awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{exit} f && NF {found=1} END{exit !found}' CHANGELOG.md \
	  || { echo "ERROR: CHANGELOG.md [Unreleased] section is empty — write the notes first"; exit 1; }
	$(MAKE) test
	perl -pi -e 's/^## \[Unreleased\]$$/## [Unreleased]\n\n## [$(V)] - '"$$(date +%Y-%m-%d)"'/' CHANGELOG.md
	git add CHANGELOG.md
	git commit -m "Release v$(V)"
	git tag "v$(V)"
	git push origin main "v$(V)"
	@echo "v$(V) pushed — CI will attach P99-Installer.zip with these notes."

test:
	swift run -c release --package-path app p99tests
	./scripts/tests.sh

# Line-coverage report over P99Core (the testable logic). Writes:
#   dist/coverage.txt          per-file table (also printed)
#   dist/coverage-percent.txt  the total line-coverage number, e.g. "93.1"
COVBIN := app/.build/debug/p99tests

coverage:
	mkdir -p $(DIST)
	swift build --package-path app -Xswiftc -profile-generate -Xswiftc -profile-coverage-mapping
	LLVM_PROFILE_FILE="$(abspath $(DIST))/p99tests.profraw" "$(COVBIN)"
	xcrun llvm-profdata merge -sparse "$(DIST)/p99tests.profraw" -o "$(DIST)/p99tests.profdata"
	xcrun llvm-cov report "$(COVBIN)" -instr-profile "$(DIST)/p99tests.profdata" \
	  -ignore-filename-regex 'Sources/p99tests' | tee "$(DIST)/coverage.txt"
	@xcrun llvm-cov export -summary-only "$(COVBIN)" -instr-profile "$(DIST)/p99tests.profdata" \
	  -ignore-filename-regex 'Sources/p99tests' > "$(DIST)/coverage.json"
	@python3 -c "import json; print(round(json.load(open('$(DIST)/coverage.json'))['data'][0]['totals']['lines']['percent'], 1))" > "$(DIST)/coverage-percent.txt"
	@echo "Total line coverage: $$(cat $(DIST)/coverage-percent.txt)%"

app:
	swift build -c release --package-path app
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BINARY)" "$(APP)/Contents/MacOS/P99Installer"
	cp app/Resources/Info.plist "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	cp app/Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	# The scripts stay the source of truth in scripts/; each build bundles a
	# fresh copy so the .app is fully self-contained.
	cp -R scripts "$(APP)/Contents/Resources/scripts"
	codesign --force --deep --sign - "$(APP)"
	@echo "Built: $(APP)  (unsigned build — first open needs right-click -> Open)"

# Experimental distribution channel. It deliberately shares the production
# sources and scripts so fixes cannot drift, but has a different app name,
# bundle identifier, and UserDefaults domain. Building it does not modify the
# stable installer artifact or an installed /Applications/P99.app wrapper.
beta:
	swift build -c release --package-path app
	rm -rf "$(BETA_APP)"
	mkdir -p "$(BETA_APP)/Contents/MacOS" "$(BETA_APP)/Contents/Resources"
	cp "$(BINARY)" "$(BETA_APP)/Contents/MacOS/P99Installer"
	cp app/Resources/Info.plist "$(BETA_APP)/Contents/Info.plist"
	plutil -replace CFBundleName -string "$(BETA_NAME)" "$(BETA_APP)/Contents/Info.plist"
	plutil -replace CFBundleDisplayName -string "$(BETA_NAME)" "$(BETA_APP)/Contents/Info.plist"
	plutil -replace CFBundleIdentifier -string "com.p99mac.installer.fex-beta" "$(BETA_APP)/Contents/Info.plist"
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(BETA_APP)/Contents/Info.plist"
	plutil -replace P99BuildChannel -string "fex-beta" "$(BETA_APP)/Contents/Info.plist"
	cp app/Resources/AppIcon.icns "$(BETA_APP)/Contents/Resources/AppIcon.icns"
	cp -R scripts "$(BETA_APP)/Contents/Resources/scripts"
	codesign --force --deep --sign - "$(BETA_APP)"
	@echo "Built: $(BETA_APP)  (experimental channel; stable installer untouched)"

beta-zip: beta
	ditto -c -k --keepParent "$(BETA_APP)" "$(BETA_ZIP)"
	@echo "Built: $(BETA_ZIP)"

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

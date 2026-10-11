#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export SDK_V10=0
: "${CVP_SIGN_IDENTITY:?Set CVP_SIGN_IDENTITY to an existing Developer ID Application identity for the isolated prototype}"
[[ "$CVP_SIGN_IDENTITY" != "-" ]]
mkdir -p build/Vendor build/logs build/symbols
PL_REV=0254f941c646b1ed17b243654723d0f071e990d0
PL_SOURCE="$ROOT/build/Vendor/plcrashreporter"
if [[ ! -d "$PL_SOURCE/.git" ]]; then
  git clone --depth 1 --branch 1.12.2 https://github.com/microsoft/plcrashreporter.git "$PL_SOURCE" > build/logs/pl-fetch.log 2>&1
fi
[[ "$(git -C "$PL_SOURCE" rev-parse HEAD)" == "$PL_REV" ]]
[[ -z "$(git -C "$PL_SOURCE" status --porcelain --untracked-files=no)" ]]
# Xcode 16.2's standalone SwiftPM resource accessor fails for upstream mixed C/C++.
# Use the upstream static-framework target unchanged; do not patch dependency sources.
xcodebuild -project "$PL_SOURCE/CrashReporter.xcodeproj" -scheme 'CrashReporter macOS Static Framework' \
  -configuration Release -sdk macosx -destination 'generic/platform=macOS' \
  -derivedDataPath "$ROOT/build/PLDerived" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
  GCC_GENERATE_DEBUGGING_SYMBOLS=YES > build/logs/plcrash-build.log 2>&1
rm -rf "$ROOT/build/Vendor/CrashReporter.xcframework"
xcodebuild -create-xcframework \
  -framework "$ROOT/build/PLDerived/Build/Products/Release-macosx-static/CrashReporter.framework" \
  -output "$ROOT/build/Vendor/CrashReporter.xcframework" > build/logs/plcrash-xcframework.log 2>&1
python3 Scripts/prepare-startup-rehearsal.py
swift build -c release -Xswiftc -g > build/logs/swift-release.log 2>&1
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/build/CrashVisibilityPrototype.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN_DIR/CrashVisibilityPrototype" "$APP/Contents/MacOS/CrashVisibilityPrototype"
xcrun clang -arch arm64 -mmacosx-version-min=12.0 -c -O2 -g \
  -fno-omit-frame-pointer -fvisibility=hidden Fixture/CrashFixture.c -o "$ROOT/build/CrashFixture.o"
xcrun clang -arch arm64 -mmacosx-version-min=12.0 -dynamiclib -g \
  -install_name '@rpath/libCVPCrashFixture.dylib' "$ROOT/build/CrashFixture.o" \
  -o "$APP/Contents/Frameworks/libCVPCrashFixture.dylib"
# Extract symbols before stripping; only these two images are the G0 symbolication gate.
xcrun dsymutil "$APP/Contents/MacOS/CrashVisibilityPrototype" -o "$ROOT/build/symbols/CrashVisibilityPrototype.dSYM" > build/logs/dsym-app.log 2>&1
xcrun dsymutil "$APP/Contents/Frameworks/libCVPCrashFixture.dylib" -o "$ROOT/build/symbols/libCVPCrashFixture.dylib.dSYM" > build/logs/dsym-c.log 2>&1
python3 Scripts/package-metadata.py
# Include upstream privacy declarations and license notices in the standalone prototype.
cp "$PL_SOURCE/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PLCrashReporter-PrivacyInfo.xcprivacy"
cp "$PL_SOURCE/LICENSE" "$APP/Contents/Resources/PLCrashReporter-LICENSE.txt"
cp .build/checkouts/sentry-cocoa/LICENSE.md "$APP/Contents/Resources/Sentry-LICENSE.txt"
SENTRY_PRIVACY="$(find .build/artifacts/sentry-cocoa/Sentry/Sentry.xcframework/macos-* -name PrivacyInfo.xcprivacy -print -quit)"
[[ -n "$SENTRY_PRIVACY" ]]
cp "$SENTRY_PRIVACY" "$APP/Contents/Resources/Sentry-PrivacyInfo.xcprivacy"
xcrun strip -S "$APP/Contents/MacOS/CrashVisibilityPrototype" "$APP/Contents/Frameworks/libCVPCrashFixture.dylib"
# Local prototype only: same-team Developer ID signatures preserve library validation.
# No timestamp/notarization/public release; no entitlement weakens Hardened Runtime.
codesign --force --sign "$CVP_SIGN_IDENTITY" --options runtime --timestamp=none "$APP/Contents/Frameworks/libCVPCrashFixture.dylib" > build/logs/sign-c.log 2>&1
codesign --force --sign "$CVP_SIGN_IDENTITY" --options runtime --timestamp=none "$APP" > build/logs/sign-app.log 2>&1
python3 Scripts/verify-package.py
printf '%s\n' "$APP"

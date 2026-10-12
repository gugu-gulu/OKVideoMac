#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${OKVIDEOMAC_BUILD_ROOT:-$PROJECT/Vendor/Build}"
CACHE="$BUILD_ROOT/CrashReporter"
SOURCE="$CACHE/Source"
REVISION=0254f941c646b1ed17b243654723d0f071e990d0
mkdir -p "$CACHE" "$PROJECT/Packages/OKCrashDiagnostics/Vendor"
if [[ ! -d "$SOURCE/.git" ]]; then
  git clone --depth 1 --branch 1.12.2 https://github.com/microsoft/plcrashreporter.git "$SOURCE"
fi
[[ "$(git -C "$SOURCE" rev-parse HEAD)" == "$REVISION" ]]
[[ -z "$(git -C "$SOURCE" status --porcelain --untracked-files=no)" ]]
export SDK_V10=0
xcodebuild -quiet -project "$SOURCE/CrashReporter.xcodeproj" \
  -scheme 'CrashReporter macOS Static Framework' -configuration Release \
  -sdk macosx -destination 'generic/platform=macOS' \
  -derivedDataPath "$CACHE/DerivedData" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym GCC_GENERATE_DEBUGGING_SYMBOLS=YES
FRAMEWORK="$CACHE/DerivedData/Build/Products/Release-macosx-static/CrashReporter.framework"
STAGE="$(mktemp -d "$CACHE/xcframework.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
xcodebuild -create-xcframework -framework "$FRAMEWORK" -output "$STAGE/CrashReporter.xcframework"
DESTINATION="$PROJECT/Packages/OKCrashDiagnostics/Vendor/CrashReporter.xcframework"
rm -rf "$DESTINATION"
cp -R "$STAGE/CrashReporter.xcframework" "$DESTINATION"
RESOURCE="$PROJECT/Packages/OKCrashDiagnostics/Sources/OKCrashDiagnostics/Resources"
cmp "$SOURCE/LICENSE" "$RESOURCE/PLCrashReporter-LICENSE.txt"
cmp "$SOURCE/Resources/PrivacyInfo.xcprivacy" "$RESOURCE/PrivacyInfo.xcprivacy"
echo 'Prepared pinned PLCrashReporter 1.12.2 static arm64 input; upstream source unchanged.'

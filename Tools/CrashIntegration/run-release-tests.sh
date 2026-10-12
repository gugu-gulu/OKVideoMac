#!/bin/bash
set -euo pipefail
ROOT="${CRASH_INTEGRATION_ROOT:-/private/tmp/OKVideoMac-CrashIntegration}"
STAGE="${1:?stage name required}"
shift
export OKVIDEOMAC_BUILD_ROOT="$ROOT/Inputs"
export OKVIDEOMAC_NODE_RUNTIME="$ROOT/Inputs/Node/bin/node"
xcodebuild -quiet \
  -project OKVideoMac/macOS/OKVideoMac/OKVideoMac.xcodeproj \
  -scheme OKVideoMac -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$ROOT/DerivedData" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=YES ENABLE_CODE_COVERAGE=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=OKVIDEO_PERFORMANCE_TEST \
  'PRODUCT_BUNDLE_IDENTIFIER=com.okvideomac.crashintegration.$(PRODUCT_NAME:rfc1034identifier)' \
  "OKVIDEOMAC_SPARKLE_ROOT=$ROOT/Inputs/Sparkle" \
  CODE_SIGN_ENTITLEMENTS=Supporting/OKVideoMac.dev.entitlements \
  -only-testing:OKVideoMacTests/DanmakuTextRasterizationTests \
  -only-testing:OKVideoMacTests/Danmaku127SessionTests \
  -only-testing:OKVideoMacTests/AppUpdateTests \
  -only-testing:OKVideoMacTests/PlaybackDisplaySleepTests \
  -only-testing:OKVideoMacTests/OKVideoMacTests/testApplicationBundleProhibitsMultipleInstances \
  -only-testing:OKVideoMacTests/OKVideoMacTests/testApplicationInstancePolicyFindsOnlyAnotherProcess \
  -only-testing:OKVideoMacTests/OKVideoMacTests/testApplicationInstanceLeaseIsExclusiveAndReleases \
  -only-testing:OKVideoMacTests/OKVideoMacTests/testXCTestHostUsesIsolatedRuntimeDirectories \
  -only-testing:OKVideoMacTests/OKVideoMacTests/testProductionRuntimeDoesNotUseTestDirectoryPolicy \
  -only-testing:OKVideoMacTests/OKVideoMacTests/testRelaunchCoordinatorArmsHelperBeforeTermination \
  -only-testing:OKVideoMacTests/OKVideoMacTests/testRelaunchCoordinatorKeepsAppRunningWhenHelperFails \
  -only-testing:OKVideoMacTests/OKVideoMacTests/testRelaunchCoordinatorStartsOnlyOneConcurrentHelper \
  "$@" test > "$ROOT/logs/$STAGE-release-tests.log" 2>&1

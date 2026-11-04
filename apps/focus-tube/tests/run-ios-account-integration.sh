#!/bin/bash
# Run on macOS/Xcode. All network, browser and Keychain dependencies are fakes.
set -euo pipefail
cd "$(dirname "$0")/.."

# Reuse a generated project but copy the small source inputs to a separate
# temporary project. Never change the project's production source in place.
mkdir -p build/ios
PROJECT=$(find build/ios -maxdepth 2 -name FocusTubeNative.xcodeproj -print -quit)
if [ -z "$PROJECT" ]; then
  node scripts/build-native-ios.mjs > /tmp/focus-account-device-build.log 2>&1 || { tail -100 /tmp/focus-account-device-build.log; exit 1; }
  PROJECT=$(find build/ios -maxdepth 2 -name FocusTubeNative.xcodeproj -print -quit)
fi
test -n "$PROJECT"
WORK=$(dirname "$PROJECT")
TEST_WORK=$(mktemp -d "${TMPDIR:-/tmp/}focus-account-test.XXXXXX")
trap 'rm -rf "$TEST_WORK"' EXIT
cp -R "$PROJECT" "$TEST_WORK/FocusTubeNative.xcodeproj"
cp -R "$WORK/Assets.xcassets" "$TEST_WORK/Assets.xcassets"
cp "$WORK/filter.js" "$TEST_WORK/filter.js"
if [ -f "$WORK/GoogleConfig.plist" ]; then cp "$WORK/GoogleConfig.plist" "$TEST_WORK/GoogleConfig.plist"; fi
PROJECT="$TEST_WORK/FocusTubeNative.xcodeproj"
cat ios/FocusPolicy.swift ios/FocusOAuthForm.swift ios/FocusRecommendations.swift ios/FocusDiagnostics.swift ios/FocusYouTubeAccount.swift tests/FocusYouTubeAccountIntegrationTests.swift > "$TEST_WORK/FocusApp.swift"

xcodebuild -project "$PROJECT" -scheme FocusTubeNative -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/account-test \
  CODE_SIGNING_ALLOWED=NO 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=FOCUS_ACCOUNT_TESTING' \
  PRODUCT_BUNDLE_IDENTIFIER=dev.palamabron.focustube.accounttests build > /tmp/focus-account-test-build.log 2>&1 \
  || { tail -100 /tmp/focus-account-test-build.log; exit 1; }

DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for group in d["devices"].values() for v in group if "iPhone" in v["name"]))')
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" build/account-test/Build/Products/Debug-iphonesimulator/FocusTubeNative.app
perl -e 'alarm shift; exec @ARGV' 240 xcrun simctl launch --console --terminate-running-process "$DEVICE" dev.palamabron.focustube.accounttests > /tmp/focus-account-test-output.log 2>&1 || true
cat /tmp/focus-account-test-output.log
grep -q 'FOCUS_ACCOUNT_TESTS_PASSED' /tmp/focus-account-test-output.log

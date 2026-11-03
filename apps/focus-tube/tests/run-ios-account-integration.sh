#!/bin/bash
# Run on macOS/Xcode. All network, browser and Keychain dependencies are fakes.
set -euo pipefail
cd "$(dirname "$0")/.."

# Reuse the production project generator, then replace only the generated test
# project's source. Production source files and the IPA are not overwritten.
node scripts/build-native-ios.mjs > /tmp/focus-account-device-build.log 2>&1 || { tail -100 /tmp/focus-account-device-build.log; exit 1; }
PROJECT=$(find build/ios -maxdepth 2 -name FocusTubeNative.xcodeproj -print -quit)
test -n "$PROJECT"
WORK=$(dirname "$PROJECT")
cat ios/FocusPolicy.swift ios/FocusOAuthForm.swift ios/FocusYouTubeAccount.swift tests/FocusYouTubeAccountIntegrationTests.swift > "$WORK/FocusApp.swift"

xcodebuild -project "$PROJECT" -scheme FocusTubeNative -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/account-test \
  CODE_SIGNING_ALLOWED=NO 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=FOCUS_ACCOUNT_TESTING' \
  PRODUCT_BUNDLE_IDENTIFIER=dev.palamabron.focustube.accounttests build > /tmp/focus-account-test-build.log 2>&1 \
  || { tail -100 /tmp/focus-account-test-build.log; exit 1; }

DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for group in d["devices"].values() for v in group if "iPhone" in v["name"]))')
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" build/account-test/Build/Products/Debug-iphonesimulator/FocusTubeNative.app
xcrun simctl launch --console --terminate-running-process "$DEVICE" dev.palamabron.focustube.accounttests > /tmp/focus-account-test-output.log 2>&1 || true
cat /tmp/focus-account-test-output.log
grep -q 'FOCUS_ACCOUNT_TESTS_PASSED' /tmp/focus-account-test-output.log

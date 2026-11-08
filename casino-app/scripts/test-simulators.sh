#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Supply available simulator names from `xcrun simctl list devices available`.
SMALL_IPHONE="${SMALL_IPHONE:-iPhone SE (3rd generation)}"
LARGE_IPHONE="${LARGE_IPHONE:-iPhone 16 Pro Max}"
ONLINE_TESTS="${ACCESSHUB_RUN_ONLINE_TESTS:-0}"
# Simulator Keychain access needs the app's normal local signing entitlements.
# This ad hoc simulator identity needs no Apple developer certificate.
mkdir -p build
for DEVICE_NAME in "$SMALL_IPHONE" "$LARGE_IPHONE"; do
  RESULT_NAME="$(echo "$DEVICE_NAME" | tr ' ()' '___')"
  xcodebuild -project AccessHubCasino.xcodeproj -scheme AccessHubCasino \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
    -resultBundlePath "build/$RESULT_NAME-$(date +%s).xcresult" \
    ACCESSHUB_RUN_ONLINE_TESTS="$ONLINE_TESTS" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
done

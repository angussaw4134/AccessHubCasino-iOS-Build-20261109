#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer team ID}"
mkdir -p build
xcodebuild -project AccessHubCasino.xcodeproj -scheme AccessHubCasino -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/AccessHubCasino.xcarchive \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" -allowProvisioningUpdates archive
cp ExportOptions.plist build/ExportOptions.plist
/usr/libexec/PlistBuddy -c "Set :teamID $APPLE_TEAM_ID" build/ExportOptions.plist
# Override EXPORT_METHOD=app-store-connect for App Store/TestFlight export or
# release-testing for registered device distribution using current Xcode.
if [[ -n "${EXPORT_METHOD:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :method $EXPORT_METHOD" build/ExportOptions.plist
fi
xcodebuild -exportArchive -archivePath build/AccessHubCasino.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
echo 'Exported signed IPA under ios/build/export.'

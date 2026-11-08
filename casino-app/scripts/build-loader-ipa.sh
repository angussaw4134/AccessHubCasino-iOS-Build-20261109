#!/bin/bash
# Build an arm64 device IPA for a loader that performs Apple-account re-signing.
# This does not create a distribution-signed or directly installable IPA.
set -euo pipefail

ios_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$ios_root/build/loader"
output_root="${ACCESSHUB_IPA_OUTPUT_DIR:-$build_root/output}"
mkdir -p "$build_root" "$output_root"
output_root="$(cd "$output_root" && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'This build requires macOS with Xcode and the iPhoneOS SDK.' >&2
  exit 1
fi
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version

# Keep this array nonempty for macOS's system Bash 3.2 with nounset enabled.
build_options=('CODE_SIGNING_ALLOWED=NO')
if [[ -n "${ACCESSHUB_API_BASE_URL:-}" ]]; then
  if [[ "$ACCESSHUB_API_BASE_URL" != https://* ]]; then
    echo 'ACCESSHUB_API_BASE_URL must be an HTTPS URL.' >&2
    exit 1
  fi
  build_options+=("ACCESSHUB_API_BASE_URL=$ACCESSHUB_API_BASE_URL")
fi

xcodebuild \
  -project "$ios_root/AccessHubCasino.xcodeproj" \
  -scheme AccessHubCasino \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_root/DerivedData" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' \
  ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES \
  "${build_options[@]}" \
  build 2>&1 | tee "$output_root/device-build.log"

app_path="$build_root/DerivedData/Build/Products/Release-iphoneos/AccessHubCasino.app"
test -d "$app_path"
staging="$(mktemp -d "$build_root/package.XXXXXX")"
mkdir -p "$staging/Payload"
ditto --norsrc "$app_path" "$staging/Payload/AccessHubCasino.app"
ditto -c -k --keepParent --norsrc "$staging/Payload" "$staging/AccessHubCasino.ipa"
cp "$staging/AccessHubCasino.ipa" "$output_root/AccessHubCasino.ipa"

python3 - "$app_path" "$output_root/AccessHubCasino.ipa" <<'PY'
from pathlib import Path
import hashlib
import json
import plistlib
import re
import subprocess
import sys
import zipfile

app = Path(sys.argv[1])
ipa = Path(sys.argv[2])
with (app / 'Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
assert 'iPhoneOS' in info.get('CFBundleSupportedPlatforms', []), 'Expected an iPhoneOS device app'
assert info['CFBundleIdentifier'] == 'app.accesshub.casino', 'Unexpected bundle identifier'
binary = app / info['CFBundleExecutable']
architectures = subprocess.check_output(['xcrun', 'lipo', '-archs', str(binary)], text=True).strip().split()
assert architectures == ['arm64'], f'Expected arm64 only: {architectures}'
build_version = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
assert re.search(r'platform\s+IOS\b', build_version), 'Binary must target iOS, not iOS Simulator'
assert not (app / 'embedded.mobileprovision').exists(), 'Unsigned loader IPA must not contain an unrelated provisioning profile'
assert info.get('AccessHubAPIBaseURL', '').startswith('https://'), 'Missing HTTPS API endpoint'
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None
    assert 'Payload/AccessHubCasino.app/Info.plist' in archive.namelist()
    assert 'Payload/AccessHubCasino.app/' + info['CFBundleExecutable'] in archive.namelist()
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
manifest = {
    'name': 'AccessHub Casino',
    'file': ipa.name,
    'bundleIdentifier': info['CFBundleIdentifier'],
    'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'],
    'minimumOSVersion': info.get('MinimumOSVersion'),
    'platforms': info['CFBundleSupportedPlatforms'],
    'architectures': architectures,
    'apiBaseURL': info['AccessHubAPIBaseURL'],
    'bytes': ipa.stat().st_size,
    'sha256': digest,
    'requiresLoaderSigning': True,
    'signing': 'Unsigned device build. The loader must sign with the installing Apple account and provision the connected iPhone.',
}
(ipa.parent / 'AccessHubCasino-build.json').write_text(json.dumps(manifest, indent=2) + '\n')
(ipa.parent / 'AccessHubCasino.ipa.sha256').write_text(digest + '  ' + ipa.name + '\n')
print(json.dumps(manifest, indent=2))
PY

echo "Loader-ready device package: $output_root/AccessHubCasino.ipa"

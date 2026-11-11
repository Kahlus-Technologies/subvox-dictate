#!/bin/bash
# Build dist/SubvoxDictate.dmg: Release build, ad-hoc signed with the app's entitlements.
# ponytail: ad-hoc signature (no Developer ID), so friends need right-click > Open once and must re-grant
# permissions after each new build. Upgrade path: Developer ID cert + notarytool + stapler.
set -euo pipefail
cd "$(dirname "$0")/.."
DD="${DERIVED_DATA:-build/rel}"
xcodebuild -scheme Hex -configuration Release -destination 'platform=macOS' -derivedDataPath "$DD" \
  -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= build -quiet
APP="$DD/Build/Products/Release/Subvox Dictate.app"
codesign --force --deep --options runtime --entitlements Hex/Hex.entitlements -s - "$APP"
rm -rf dist && mkdir -p dist/stage
cp -R "$APP" dist/stage/
ln -s /Applications dist/stage/Applications
hdiutil create -quiet -volname "Subvox Dictate" -srcfolder dist/stage -ov -format UDZO dist/SubvoxDictate.dmg
rm -rf dist/stage
echo "built dist/SubvoxDictate.dmg"

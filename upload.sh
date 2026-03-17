#!/bin/bash
# LoadScan — Archive & Upload to TestFlight
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/ApplianceManifest.xcodeproj"
SCHEME="ApplianceManifest"
ARCHIVE="$PROJECT_DIR/build/ApplianceManifest.xcarchive"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"

echo "▶ Cleaning build folder..."
rm -rf "$PROJECT_DIR/build"
mkdir -p "$PROJECT_DIR/build"

echo "▶ Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE=Automatic \

echo "▶ Uploading to App Store Connect (TestFlight)..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$PROJECT_DIR/build/export" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

echo ""
echo "✓ Upload complete. Go to:"
echo "  https://appstoreconnect.apple.com → Apps → LoadScan → TestFlight"
echo "  Enable a Public Link under External Testing."

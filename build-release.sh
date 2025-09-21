#!/bin/bash

# Configuration - Update these with your values
APP_NAME="TempurAI"
BUNDLE_ID="com.setrf.tempur"      # Your unique bundle ID

# Apple Developer credentials - Set these as environment variables
DEVELOPER_ID="${DEVELOPER_ID:-}"  # Your Apple Developer name/email
NOTARIZATION_ACCOUNT="${NOTARIZATION_ACCOUNT:-}"  # Your Apple ID email
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"  # Your Team ID
NOTARIZATION_PASSWORD="${NOTARIZATION_PASSWORD:-}"  # Your app-specific password
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"  # Your Developer ID Application certificate hash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Building and signing $APP_NAME...${NC}"

# Clean previous builds
echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
rm -rf .build
rm -rf dist

# Build the application
echo -e "${YELLOW}🔨 Building application...${NC}"
swift build -c release --arch arm64 --arch x86_64

# Create app bundle structure
echo -e "${YELLOW}📦 Creating app bundle...${NC}"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp .build/apple/Products/Release/tempur "$MACOS_DIR/$APP_NAME"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Code sign the app
echo -e "${YELLOW}🔐 Code signing application...${NC}"
# Use the Developer ID Application certificate
if [ -z "$DEVELOPER_ID_APPLICATION" ]; then
    echo -e "${RED}❌ Error: DEVELOPER_ID_APPLICATION not set${NC}"
    echo -e "${YELLOW}💡 Set your Developer ID Application certificate hash in DEVELOPER_ID_APPLICATION${NC}"
    exit 1
fi

codesign --force --deep --options runtime --sign "$DEVELOPER_ID_APPLICATION" --entitlements entitlements.plist "$APP_BUNDLE"

# Verify signature
echo -e "${YELLOW}✅ Verifying code signature...${NC}"
codesign --verify --verbose "$APP_BUNDLE"

# Create DMG
echo -e "${YELLOW}💿 Creating DMG...${NC}"
DMG_NAME="$APP_NAME.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_NAME"

# Code sign the DMG
echo -e "${YELLOW}🔐 Code signing DMG...${NC}"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" "$DMG_NAME"

# Notarize the DMG
echo -e "${YELLOW}📝 Notarizing with Apple...${NC}"
if [ -z "$NOTARIZATION_ACCOUNT" ]; then
    echo -e "${RED}❌ Error: NOTARIZATION_ACCOUNT not set${NC}"
    echo -e "${YELLOW}💡 Set your Apple ID email in NOTARIZATION_ACCOUNT${NC}"
    exit 1
fi

if [ -z "$NOTARIZATION_PASSWORD" ]; then
    echo -e "${RED}❌ Error: NOTARIZATION_PASSWORD not set${NC}"
    echo -e "${YELLOW}💡 Set your app-specific password in NOTARIZATION_PASSWORD${NC}"
    exit 1
fi

if [ -z "$APPLE_TEAM_ID" ]; then
    echo -e "${RED}❌ Error: APPLE_TEAM_ID not set${NC}"
    echo -e "${YELLOW}💡 Set your Apple Team ID in APPLE_TEAM_ID${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Using Developer ID Application certificate for notarization${NC}"

# Submit for notarization
NOTARIZATION_UUID=$(xcrun notarytool submit "$DMG_NAME" --apple-id "$NOTARIZATION_ACCOUNT" --password "$NOTARIZATION_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}' | head -1)

echo -e "${GREEN}📋 Notarization UUID: $NOTARIZATION_UUID${NC}"

# Check notarization status
xcrun notarytool info "$NOTARIZATION_UUID" --apple-id "$NOTARIZATION_ACCOUNT" --password "$NOTARIZATION_PASSWORD" --team-id "$APPLE_TEAM_ID"

# Staple the notarization ticket
echo -e "${YELLOW}📌 Stapling notarization ticket...${NC}"
xcrun stapler staple "$DMG_NAME"

# Verify notarization
echo -e "${YELLOW}✅ Verifying notarization...${NC}"
xcrun stapler validate "$DMG_NAME"

# Move to dist directory
echo -e "${YELLOW}📁 Moving to dist directory...${NC}"
mkdir -p dist
mv "$DMG_NAME" dist/

# Clean up
echo -e "${YELLOW}🧹 Cleaning up...${NC}"
rm -rf "$APP_BUNDLE"

echo -e "${GREEN}🎉 Build complete!${NC}"
echo -e "${GREEN}📦 DMG created: dist/$DMG_NAME${NC}"
echo -e "${GREEN}🔐 App is signed and notarized${NC}"

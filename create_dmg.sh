#!/bin/bash
set -e

echo "🧹 Cleaning up old builds..."
rm -rf build dmg_stage SpaceSweep.dmg

echo "🏗️  Building SpaceSweep (Release Mode)..."
xcodebuild -project SpaceSweep.xcodeproj -scheme SpaceSweep -configuration Release clean build CONFIGURATION_BUILD_DIR="$(pwd)/build/Release" -quiet

echo "📦 Preparing DMG contents..."
mkdir -p dmg_stage
cp -R build/Release/SpaceSweep.app dmg_stage/

# Add an Applications shortcut so users can drag-and-drop to install
ln -s /Applications dmg_stage/Applications

echo "💿 Creating SpaceSweep.dmg..."
hdiutil create -volname "SpaceSweep" -srcfolder dmg_stage -ov -format UDZO SpaceSweep.dmg

echo "🧹 Cleaning up temporary files..."
rm -rf build dmg_stage

echo "✅ Done! SpaceSweep.dmg has been created in your project folder."

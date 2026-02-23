#!/bin/bash

# Script to create a DMG file for distribution

APP_NAME="ClaudeUsage"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
VOLUME_NAME="${APP_NAME}"

echo "Creating DMG for ${APP_NAME}..."

# Check if app bundle exists
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "Error: App bundle not found at ${APP_BUNDLE}"
    echo "Please run ./build.sh first"
    exit 1
fi

# Remove existing DMG if it exists
if [ -f "${DMG_PATH}" ]; then
    echo "Removing existing DMG..."
    rm "${DMG_PATH}"
fi

# Create a temporary directory for DMG contents
DMG_TMP_DIR=$(mktemp -d)
echo "Using temporary directory: ${DMG_TMP_DIR}"

# Copy app bundle to temp directory
cp -R "${APP_BUNDLE}" "${DMG_TMP_DIR}/"

# Create a symbolic link to /Applications
ln -s /Applications "${DMG_TMP_DIR}/Applications"

# Create the DMG
echo "Creating DMG file..."
hdiutil create -volname "${VOLUME_NAME}" \
    -srcfolder "${DMG_TMP_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

# Clean up
rm -rf "${DMG_TMP_DIR}"

if [ $? -eq 0 ]; then
    echo "DMG created successfully at ${DMG_PATH}"
    echo ""
    echo "File size:"
    ls -lh "${DMG_PATH}" | awk '{print $5, $9}'
else
    echo "Failed to create DMG!"
    exit 1
fi

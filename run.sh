#!/bin/bash

# Run script for Claude Usage menubar app

APP_NAME="ClaudeUsage"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

# Check if app exists
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "App not found. Building first..."
    ./build.sh
fi

# Kill existing instance if running
pkill -f "${APP_NAME}" 2>/dev/null && sleep 1

echo "Starting ${APP_NAME}..."
open "${APP_BUNDLE}"

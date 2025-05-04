#!/bin/bash

# --- Configuration ---
# sysargs
PROJECT=$1           # A project name
SCHEME=$2            # A scheme to build (usually matches project name)

CONFIGURATION="Debug"

SPECIFIC_SIMULATOR_UDID=""


set -e # Exit immediately if a command exits with a non-zero status.

echo " T Script Configuration:"
echo "   Project:           ${PROJECT}"
echo "   Scheme:            ${SCHEME}"
echo "   Configuration:     ${CONFIGURATION}"
echo "   Target Simulator:  ${SPECIFIC_SIMULATOR_UDID:-Auto-detect booted}"
echo "-------------------------------------"

# 1. Find the Simulator UDID
SIMULATOR_UDID=""
if [ -n "$SPECIFIC_SIMULATOR_UDID" ]; then
    echo " Using specified simulator UDID: ${SPECIFIC_SIMULATOR_UDID}"
    SIMULATOR_UDID="$SPECIFIC_SIMULATOR_UDID"
    # Optional: Check if it's actually booted
    if ! xcrun simctl list devices booted | grep -q "$SIMULATOR_UDID"; then
       echo " Error: Specified simulator ${SIMULATOR_UDID} is not booted."
       exit 1
    fi
else
    echo " Detecting booted simulator..."
    # Get the UDID of the first booted simulator - improved to handle whitespace better
    SIMULATOR_UDID=$(xcrun simctl list devices booted | grep -E '\(Booted\)' | head -n 1 | sed -E 's/.*\(([A-Z0-9\-]+)\).*/\1/')

    if [ -z "$SIMULATOR_UDID" ]; then
        echo " Error: No booted simulator found. Please start a simulator."
        exit 1
    else
        SIMULATOR_INFO=$(xcrun simctl list devices booted | grep "$SIMULATOR_UDID" | head -n 1 | xargs)
        echo " Found booted simulator: ${SIMULATOR_INFO}"
    fi
fi

# 2. Determine Build Settings (App Path and Bundle ID)
echo " Determining build settings..."
BUILD_SETTINGS=$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -sdk iphonesimulator -configuration "${CONFIGURATION}" -showBuildSettings)

if [ $? -ne 0 ]; then
    echo " Error: Failed to get build settings. Check project/scheme name and Xcode setup."
    exit 1
fi

TARGET_BUILD_DIR=$(echo "${BUILD_SETTINGS}" | grep -w 'TARGET_BUILD_DIR' | head -n 1 | awk -F '= ' '{print $2}' | xargs)
WRAPPER_NAME=$(echo "${BUILD_SETTINGS}" | grep -w 'WRAPPER_NAME' | head -n 1 | awk -F '= ' '{print $2}' | xargs)
PRODUCT_BUNDLE_IDENTIFIER=$(echo "${BUILD_SETTINGS}" | grep -w 'PRODUCT_BUNDLE_IDENTIFIER' | head -n 1 | awk -F '= ' '{print $2}' | xargs)

if [ -z "$TARGET_BUILD_DIR" ] || [ -z "$WRAPPER_NAME" ] || [ -z "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
    echo " Error: Could not parse required build settings (TARGET_BUILD_DIR, WRAPPER_NAME, PRODUCT_BUNDLE_IDENTIFIER)."
    echo " Check your Xcode project configuration and scheme settings."
    exit 1
fi

APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"

echo "   App Path:          ${APP_PATH}"
echo "   Bundle Identifier: ${PRODUCT_BUNDLE_IDENTIFIER}"

# 3. Build the project for the simulator
echo " Building project..."
xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -sdk iphonesimulator \
    -configuration "${CONFIGURATION}" \
    -destination "id=${SIMULATOR_UDID}" \
    build # Use 'clean build' if you want to clean first

if [ $? -ne 0 ]; then
    echo " Error: Xcode build failed."
    exit 1
fi

echo " Build successful!"

# 4. Check if App Path exists
if [ ! -d "$APP_PATH" ]; then
    echo " Error: Built app not found at expected path: ${APP_PATH}"
    echo " Check derived data paths or build settings."
    exit 1
fi

# 5. Install the app onto the simulator
echo " Installing app on simulator ${SIMULATOR_UDID}..."
xcrun simctl install "${SIMULATOR_UDID}" "${APP_PATH}"

if [ $? -ne 0 ]; then
    echo " Error: Failed to install app on simulator."
    exit 1
fi

echo " Installation successful!"

# 6. Launch the app on the simulator
echo " Launching app (${PRODUCT_BUNDLE_IDENTIFIER}) on simulator..."
xcrun simctl launch "${SIMULATOR_UDID}" "${PRODUCT_BUNDLE_IDENTIFIER}"

if [ $? -ne 0 ]; then
    echo " Error: Failed to launch app on simulator."
    echo " Attempting to terminate existing instance first..."
    xcrun simctl terminate "${SIMULATOR_UDID}" "${PRODUCT_BUNDLE_IDENTIFIER}" || true # Ignore error if not running
    sleep 1
    xcrun simctl launch "${SIMULATOR_UDID}" "${PRODUCT_BUNDLE_IDENTIFIER}"
    if [ $? -ne 0 ]; then
       echo " Error: Still failed to launch app."
       exit 1
    fi
fi

echo " App launched successfully!"
echo "-------------------------------------"
echo " T Script finished."

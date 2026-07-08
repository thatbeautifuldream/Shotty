#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$PROJECT_DIR/Shotty.xcodeproj"
SCHEME="Shotty"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$PROJECT_DIR/.derived-data"
SCREENSHOT_DIR="$PROJECT_DIR/screenshots"
BUNDLE_ID="com.milind.Shotty"
RUN_DESTINATION="${RUN_DESTINATION:-simulator}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
SIMULATOR_RUNTIME="${SIMULATOR_RUNTIME:-iOS 26.2}"

mkdir -p "$SCREENSHOT_DIR"

if [[ "$RUN_DESTINATION" == "device" ]]; then
  DESTINATION="generic/platform=iOS"
  PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos"

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build

  DEVICE_ID="${DEVICE_ID:-$(xcrun devicectl list devices 2>/dev/null | awk 'NR > 2 && /connected/ {print $3; exit}')}"

  if [[ -z "${DEVICE_ID:-}" ]]; then
    echo "Could not find a connected iPhone. Connect and trust the device, or set DEVICE_ID."
    exit 1
  fi

  xcrun devicectl device install app --device "$DEVICE_ID" "$PRODUCTS_DIR/$SCHEME.app"
  xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"

  echo "Launched $SCHEME on device $DEVICE_ID"
else
  if ! xcrun simctl list devices available | grep -q "$SIMULATOR_NAME"; then
    DEVICE_TYPE_ID="$(xcrun simctl list devicetypes | awk -v name="$SIMULATOR_NAME" '$0 ~ name {print $NF; exit}' | tr -d '()')"
    RUNTIME_ID="$(xcrun simctl list runtimes available | awk -v runtime="$SIMULATOR_RUNTIME" '$0 ~ runtime {print $NF; exit}' | tr -d '()')"

    if [[ -z "${DEVICE_TYPE_ID:-}" || -z "${RUNTIME_ID:-}" ]]; then
      echo "Could not find simulator '$SIMULATOR_NAME' with runtime '$SIMULATOR_RUNTIME'."
      echo "Install an iOS Simulator runtime in Xcode Settings, or set SIMULATOR_NAME and SIMULATOR_RUNTIME."
      exit 1
    fi

    xcrun simctl create "$SIMULATOR_NAME" "$DEVICE_TYPE_ID" "$RUNTIME_ID" >/dev/null
  fi

  DESTINATION="platform=iOS Simulator,name=$SIMULATOR_NAME"

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build

  APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator/$SCHEME.app"

  xcrun simctl boot "$SIMULATOR_NAME" 2>/dev/null || true
  xcrun simctl bootstatus "$SIMULATOR_NAME" -b
  xcrun simctl install "$SIMULATOR_NAME" "$APP_PATH"
  xcrun simctl launch "$SIMULATOR_NAME" "$BUNDLE_ID"
  xcrun simctl io "$SIMULATOR_NAME" screenshot "$SCREENSHOT_DIR/latest.png"

  echo "Launched $SCHEME on $SIMULATOR_NAME"
  echo "Screenshot: $SCREENSHOT_DIR/latest.png"
fi

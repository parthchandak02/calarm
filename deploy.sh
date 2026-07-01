#!/bin/bash

# Calarm - Clean iOS 26 Deployment Script
# Uses deploy-lib.sh for clean logging and utilities

set -e  # Exit on any error

# Load our utility library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/deploy-lib.sh"

# Configuration
PROJECT_NAME="Calarm.xcodeproj"
TARGET="Calarm"
CONFIGURATION="Debug"
BUILD_PATH="./build"
APP_NAME="Calarm"

# Verbose mode (set VERBOSE=true for detailed output)
VERBOSE=${VERBOSE:-false}

echo_title "📱 Calarm - iOS 26 AlarmKit Deployment"

# Parse command line arguments
DEPLOYMENT_TARGET=""
MONITOR_MODE=""

if [ $# -eq 1 ]; then
    case "$1" in
        "1")
            DEPLOYMENT_TARGET="simulator"
            log_info "🎯 Target: iOS Simulator (argument: 1)"
            ;;
        "2")
            DEPLOYMENT_TARGET="device"
            log_info "🎯 Target: Physical Device (argument: 2)"
            ;;
        "monitor"|"m")
            MONITOR_MODE="live"
            ;;
        "status"|"s")
            MONITOR_MODE="status"
            ;;
        "lifecycle"|"l")
            MONITOR_MODE="lifecycle"
            ;;
        "auth"|"a")
            MONITOR_MODE="auth"
            ;;
        "notifications"|"n")
            MONITOR_MODE="notifications"
            ;;
        *)
            log_error "Invalid argument: $1"
            echo
            echo "Usage:"
            echo "  ./deploy.sh 1               Deploy to iOS Simulator"
            echo "  ./deploy.sh 2               Deploy to Physical Device"
            echo "  ./deploy.sh monitor         Monitor Live Activities (15 sec)"
            echo "  ./deploy.sh m               Monitor Live Activities (short)"
            echo "  ./deploy.sh lifecycle       Monitor AlarmKit lifecycle (30 sec)"
            echo "  ./deploy.sh l               Monitor AlarmKit lifecycle (short)"
            echo "  ./deploy.sh auth            Check AlarmKit authorization"
            echo "  ./deploy.sh a               Check authorization (short)"
            echo "  ./deploy.sh notifications   Debug alarm notifications (20 sec)"
            echo "  ./deploy.sh n               Debug notifications (short)"
            echo "  ./deploy.sh status   Check Live Activity status"
            echo "  ./deploy.sh s        Check Live Activity status (short)"
            echo "  ./deploy.sh          Auto-detect (legacy mode)"
            exit 1
            ;;
    esac
elif [ $# -eq 2 ]; then
    case "$1" in
        "monitor"|"m")
            MONITOR_MODE="live"
            # Second argument is duration
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                MONITOR_DURATION="$2"
            else
                log_error "Invalid duration: $2 (must be number of seconds)"
                exit 1
            fi
            ;;
        "lifecycle"|"l")
            MONITOR_MODE="lifecycle"
            # Second argument is duration
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                MONITOR_DURATION="$2"
            else
                log_error "Invalid duration: $2 (must be number of seconds)"
                exit 1
            fi
            ;;
        "notifications"|"n")
            MONITOR_MODE="notifications"
            # Second argument is duration
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                MONITOR_DURATION="$2"
            else
                log_error "Invalid duration: $2 (must be number of seconds)"
                exit 1
            fi
            ;;
        *)
            log_error "Invalid arguments: $1 $2"
            echo
            echo "Usage:"
            echo "  ./deploy.sh monitor 30       Monitor Live Activities for 30 seconds"
            echo "  ./deploy.sh m 30             Monitor Live Activities for 30 seconds"
            echo "  ./deploy.sh lifecycle 45     Monitor AlarmKit lifecycle for 45 seconds"
            echo "  ./deploy.sh l 45             Monitor AlarmKit lifecycle for 45 seconds"
            echo "  ./deploy.sh notifications 25  Debug alarm notifications for 25 seconds"
            echo "  ./deploy.sh n 25             Debug notifications for 25 seconds"
            exit 1
            ;;
    esac
elif [ $# -gt 2 ]; then
    log_error "Too many arguments"
    echo
    echo "Usage:"
    echo "  ./deploy.sh 1        Deploy to iOS Simulator"
    echo "  ./deploy.sh 2        Deploy to Physical Device"
    echo "  ./deploy.sh monitor  Monitor Live Activities (15 sec)"
    echo "  ./deploy.sh status   Check Live Activity status"
    echo "  ./deploy.sh          Auto-detect (legacy mode)"
    exit 1
else
    log_info "🔍 Auto-detection mode (no arguments provided)"
fi

# Handle monitoring modes
if [ -n "$MONITOR_MODE" ]; then
    case "$MONITOR_MODE" in
        "live")
            monitor_live_activities "${MONITOR_DURATION:-15}"
            ;;
        "status")
            check_activity_status
            ;;
        "lifecycle")
            monitor_alarm_lifecycle "${MONITOR_DURATION:-30}"
            ;;
        "auth")
            check_alarm_authorization
            ;;
        "notifications")
            debug_alarm_notifications "${MONITOR_DURATION:-20}"
            ;;
    esac
    exit 0
fi

# Validate environment
check_file "$PROJECT_NAME/project.pbxproj" || {
    log_error "$PROJECT_NAME not found in current directory"
    exit 1
}

# Detect iOS 26 targets
echo_section "📋 Scanning for iOS 26.0 targets"

# Device selection based on argument or auto-detection
if [ "$DEPLOYMENT_TARGET" = "simulator" ] || [ -z "$DEPLOYMENT_TARGET" ]; then
    # Check simulators first (or force simulator with argument 1)
    # Look for specific iOS 26.0 devices, prioritize the new iPhone 16 Pro
    SIMULATORS=$(xcrun simctl list devices available | grep "iOS 26.0" | grep -E "(iPhone 16 Pro|iPhone 16)" || echo "")
    if [ -n "$SIMULATORS" ]; then
        if [ "$DEPLOYMENT_TARGET" = "simulator" ]; then
            log_info "🎯 Forced target: iOS 26.0 Simulators"
        else
            log_info "Available iOS 26.0 Simulators:"
        fi
        echo "$SIMULATORS"
        
        # Auto-select first booted simulator or first available
        # New device identifier: A2684590-2A44-4E91-A302-1D9CDB5A9472
        DEVICE_ID=$(echo "$SIMULATORS" | grep "(Booted)" | head -n1 | grep -o '[A-F0-9-]\{36\}' || \
                    echo "$SIMULATORS" | head -n1 | grep -o '[A-F0-9-]\{36\}' || \
                    echo "A2684590-2A44-4E91-A302-1D9CDB5A9472")
        DEVICE_TYPE="simulator"
        DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
        
        if echo "$SIMULATORS" | grep -q "(Booted)"; then
            log_success "Using booted simulator: $DEVICE_ID"
        else
            log_info "Using available simulator: $DEVICE_ID"
        fi
    elif [ "$DEPLOYMENT_TARGET" = "simulator" ]; then
        log_error "No iOS 26.0 iPhone simulators found (forced simulator mode)"
        exit 1
    else
        log_warning "No iOS 26.0 iPhone simulators found, checking physical devices..."
        DEPLOYMENT_TARGET="device"  # Fall back to device mode
    fi
fi

if [ "$DEPLOYMENT_TARGET" = "device" ] || [ -z "$DEVICE_TYPE" ]; then
    # Check physical devices using xctrace (same IDs as xcodebuild)
    DEVICE_LIST=$(xcrun xctrace list devices 2>/dev/null | grep -E "iPhone|iPad" | grep -v "Simulator" || echo "")
    if [ -n "$DEVICE_LIST" ]; then
        if [ "$DEPLOYMENT_TARGET" = "device" ]; then
            log_info "🎯 Forced target: Physical Devices"
        else
            log_info "Available Physical Devices:"
        fi
        echo "$DEVICE_LIST"
        
        # Extract device ID from xctrace output (format: "Device Name (Version) (ID)")
        DEVICE_ID=$(echo "$DEVICE_LIST" | head -n1 | grep -o '([A-F0-9-]*[A-F0-9])' | tail -n1 | sed 's/[()]//g')
        DEVICE_TYPE="device"
        DESTINATION="platform=iOS,id=$DEVICE_ID"
        log_success "Using physical device: $DEVICE_ID"
    else
        log_error "No physical devices found"
        if [ "$DEPLOYMENT_TARGET" = "device" ]; then
            echo
            log_info "Make sure your device is connected and trusted"
        fi
        exit 1
    fi
fi

# Final validation
if [ -z "$DEVICE_ID" ] || [ -z "$DEVICE_TYPE" ]; then
    log_error "No suitable deployment target found"
    exit 1
fi

# Clean build
echo_section "🧹 Cleaning previous builds"
    rm -rf "$BUILD_PATH"
log_success "Cleaned build directory"

# Build with Xcode bug workaround
echo_section "🔨 Building $APP_NAME"

# Block domains to prevent hanging (known Xcode 16+ bug fix)
block_domain "developerservices2.apple.com"
if [ "$DEVICE_TYPE" = "device" ]; then
    # Additional domains that can cause hanging for physical device builds
    block_domain "developer.apple.com"
    block_domain "idmsa.apple.com"
    trap 'unblock_domain "developerservices2.apple.com"; unblock_domain "developer.apple.com"; unblock_domain "idmsa.apple.com"' EXIT
else
    trap 'unblock_domain "developerservices2.apple.com"' EXIT
fi

# Build command with timeout and anti-hang flags
ANTI_HANG_FLAGS="-skipPackageSignatureValidation -skipMacroValidation -disableAutomaticPackageResolution"

if [ "$VERBOSE" = "true" ]; then
    BUILD_CMD="xcodebuild -project \"$PROJECT_NAME\" -target \"$TARGET\" -sdk iphonesimulator -configuration \"$CONFIGURATION\" -destination \"$DESTINATION\" $ANTI_HANG_FLAGS CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO SYMROOT=\"$BUILD_PATH\" -verbose build"
else
    BUILD_CMD="xcodebuild -project \"$PROJECT_NAME\" -target \"$TARGET\" -sdk iphonesimulator -configuration \"$CONFIGURATION\" -destination \"$DESTINATION\" $ANTI_HANG_FLAGS CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO SYMROOT=\"$BUILD_PATH\" build"
fi

log_step "Building with 5-minute timeout protection..."
if [ "$VERBOSE" = "true" ]; then
    log_info "Running: $BUILD_CMD"
fi

if run_with_timeout 300 eval "$BUILD_CMD"; then
    log_success "Build completed successfully!"
else
    exit_code=$?
    if [ $exit_code -eq 124 ]; then
        log_error "Build timed out after 5 minutes"
        echo
        log_info "The build process hung. Try opening the project in Xcode first to resolve any issues."
    else
        log_error "Build failed with exit code $exit_code"
    fi
    exit 1
fi

# Find built app
echo_section "🔍 Locating built app"
if [ "$DEVICE_TYPE" = "simulator" ]; then
    APP_PATH=$(find "$BUILD_PATH" -name "$APP_NAME.app" -path "*iphonesimulator*" -type d | head -n1)
else
    APP_PATH=$(find "$BUILD_PATH" -name "$APP_NAME.app" -path "*iphoneos*" -type d | head -n1)
fi

check_file "$APP_PATH/Info.plist" || {
    log_error "Built app not found in $BUILD_PATH"
    exit 1
}

log_success "Found app at: $APP_PATH"

# Install and launch
echo_section "📲 Installing and launching $APP_NAME"

if [ "$DEVICE_TYPE" = "simulator" ]; then
    # Boot simulator if needed
    log_step "Ensuring simulator is booted..."
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || log_info "Simulator already booted"
    sleep 2
    
    # Install
    [ "$VERBOSE" = "true" ] && log_info "Running: xcrun simctl install '$DEVICE_ID' '$APP_PATH'"
    if xcrun simctl install "$DEVICE_ID" "$APP_PATH"; then
        log_success "Installation successful!"
    else
        log_error "Simulator installation failed"
        exit 1
    fi
    
    # Launch
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Info.plist" 2>/dev/null || echo "")
    if [ -n "$BUNDLE_ID" ]; then
        [ "$VERBOSE" = "true" ] && log_info "Bundle ID: $BUNDLE_ID"
        if xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1; then
            log_success "App launched successfully!"
        else
            log_warning "Launch completed - check simulator"
        fi
    else
        log_warning "Could not determine bundle identifier"
    fi
    
else
    # Physical device
    [ "$VERBOSE" = "true" ] && log_info "Running: xcrun devicectl device install app --device '$DEVICE_ID' '$APP_PATH'"
    if xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"; then
        log_success "Installation successful!"
    else
        log_error "Device installation failed"
        echo
        log_info "Common solutions:"
        echo "  📱 Ensure device is unlocked and trusted"
        echo "  🔧 Check Developer Mode is enabled"
        echo "  🔑 Verify your Apple ID is signed in to Xcode"
        exit 1
    fi
    
    # Launch on device
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Info.plist" 2>/dev/null || echo "")
    if [ -n "$BUNDLE_ID" ]; then
        [ "$VERBOSE" = "true" ] && log_info "Bundle ID: $BUNDLE_ID"
        if xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1; then
            log_success "App launched successfully!"
        else
            log_warning "Launch completed - check your device"
        fi
    else
        log_warning "Could not determine bundle identifier automatically"
        log_info "Please launch the app manually from your device home screen"
    fi
fi

# Success summary
echo
log_success "🎉 Deployment complete!"
echo
log_info "📱 Your $APP_NAME is now running on $([ "$DEVICE_TYPE" = "simulator" ] && echo "iPhone 16 Pro Simulator" || echo "physical device") (iOS 26.0)!"

# Testing notes
echo
log_header "🔔 AlarmKit Testing Notes:"
echo "  • The app uses iOS 26 AlarmKit framework for countdown-based alarms"
echo "  • Test creating timer alarms with Live Activities in Dynamic Island"
echo "  • Try pause/resume functionality during countdown"
echo "  • Verify custom sounds and alert presentations work"

if [ "$DEVICE_TYPE" = "simulator" ]; then
    echo
    log_info "📲 Simulator testing tips:"
    echo "  • Use Device > Trigger Live Activity to test different states"
    echo "  • Check Dynamic Island integration"
    echo "  • Test with locked simulator (Device > Lock)"
fi

echo
log_success "Happy testing with iOS 26 AlarmKit! 🚀"
echo
log_info "💡 To enable verbose mode, run: VERBOSE=true ./deploy-clean.sh"
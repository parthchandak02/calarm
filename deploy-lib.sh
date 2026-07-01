#!/bin/bash

# deploy-lib.sh - Simple deployment utility library
# Provides clean logging, progress indicators, and utility functions

# Colors
declare -r COLOR_RED='\033[0;31m'
declare -r COLOR_GREEN='\033[0;32m'
declare -r COLOR_YELLOW='\033[1;33m'
declare -r COLOR_BLUE='\033[0;34m'
declare -r COLOR_PURPLE='\033[0;35m'
declare -r COLOR_CYAN='\033[0;36m'
declare -r COLOR_NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${COLOR_BLUE}ℹ️  $1${COLOR_NC}"
}

log_success() {
    echo -e "${COLOR_GREEN}✅ $1${COLOR_NC}"
}

log_warning() {
    echo -e "${COLOR_YELLOW}⚠️  $1${COLOR_NC}"
}

log_error() {
    echo -e "${COLOR_RED}❌ $1${COLOR_NC}"
}

log_step() {
    echo -e "${COLOR_PURPLE}🔧 $1${COLOR_NC}"
}

log_header() {
    echo -e "${COLOR_BLUE}$1${COLOR_NC}"
    echo "======================================================"
}

# Progress indicators
show_spinner() {
    local -r pid=$1
    local -r delay=0.1
    local -r frames='|/-\'
    
    while kill -0 $pid 2>/dev/null; do
        for frame in $(echo $frames | fold -w1); do
            printf "\r⏳ $2 %c" "$frame"
            sleep $delay
        done
    done
    printf "\r"
}

run_with_progress() {
    local cmd="$1"
    local msg="$2"
    
    log_step "$msg"
    if eval "$cmd" >/dev/null 2>&1; then
        log_success "$msg completed"
        return 0
    else
        log_error "$msg failed"
        return 1
    fi
}

# Utility functions
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' not found"
        return 1
    fi
}

check_file() {
    if [ ! -f "$1" ]; then
        log_error "File not found: $1"
        return 1
    fi
}

check_dir() {
    if [ ! -d "$1" ]; then
        log_error "Directory not found: $1"
        return 1
    fi
}

# Timeout wrapper with shell-based fallback
run_with_timeout() {
    local timeout_duration=$1
    shift
    
    if command -v gtimeout &> /dev/null; then
        gtimeout "$timeout_duration" "$@"
        return $?
    elif command -v timeout &> /dev/null; then
        timeout "$timeout_duration" "$@"
        return $?
    else
        # Shell-based timeout implementation
        log_info "Using shell-based timeout ($timeout_duration seconds)"
        
        # Run command in background
        "$@" &
        local cmd_pid=$!
        
        # Wait for timeout duration
        local count=0
        while [ $count -lt $timeout_duration ]; do
            if ! kill -0 $cmd_pid 2>/dev/null; then
                # Process finished
                wait $cmd_pid
                return $?
            fi
            sleep 1
            count=$((count + 1))
        done
        
        # Timeout reached - kill the process
        log_warning "Timeout reached after $timeout_duration seconds - terminating process"
        kill -TERM $cmd_pid 2>/dev/null
        sleep 2
        kill -KILL $cmd_pid 2>/dev/null
        wait $cmd_pid 2>/dev/null
        return 124  # Standard timeout exit code
    fi
}

# Domain blocking (for the xcodebuild fix)
block_domain() {
    local domain="$1"
    log_warning "Temporarily blocking $domain to prevent hanging..."
    echo "127.0.0.1 $domain" | sudo tee -a /etc/hosts > /dev/null
}

unblock_domain() {
    local domain="$1"
    log_info "Restoring access to $domain..."
    sudo sed -i '' "/$domain/d" /etc/hosts
}

# Enhanced echo functions
echo_title() {
    echo
    log_header "$1"
    echo
}

echo_section() {
    echo
    log_info "$1"
}

echo_result() {
    local status=$1
    local message="$2"
    
    if [ $status -eq 0 ]; then
        log_success "$message"
    else
        log_error "$message"
    fi
}

# Live Activity monitoring functions
monitor_live_activities() {
    local duration=${1:-15}
    echo_section "🔍 Monitoring Live Activities for ${duration} seconds"
    
    log_info "Watching for AlarmKit and ActivityKit logs..."
    log_info "Create a timer in the app now!"
    
    # Enhanced AlarmKit-specific monitoring
    run_with_timeout "$duration" xcrun simctl spawn booted log stream --predicate '
        subsystem CONTAINS "AlarmKit" OR 
        subsystem CONTAINS "ActivityKit" OR 
        subsystem CONTAINS "liveactivitiesd" OR 
        subsystem CONTAINS "mobiletimerd" OR 
        subsystem CONTAINS "AlarmKitCore" OR
        process == "Calarm" OR 
        message CONTAINS "Live Activity" OR 
        message CONTAINS "activity" OR
        message CONTAINS "systemAperture" OR
        message CONTAINS "Dynamic" OR
        message CONTAINS "preferredLayoutMode" OR
        message CONTAINS "alarm" OR
        message CONTAINS "Firing event" OR
        message CONTAINS "Transitioning" OR
        message CONTAINS "countdown" OR
        message CONTAINS "timer alert" OR
        message CONTAINS "notification"
    ' --info 2>/dev/null || true
    
    echo ""
    log_success "Monitoring completed"
}

# Quick activity status check
check_activity_status() {
    echo_section "📱 Current Live Activity Status"
    
    # Check recent logs for activity creation
    log_info "Checking recent activity creation..."
    local recent_activities=$(xcrun simctl spawn booted log show --predicate '
        (subsystem CONTAINS "AlarmKit" OR subsystem CONTAINS "ActivityKit") AND 
        (message CONTAINS "Created activity" OR message CONTAINS "activity for alarm")
    ' --info --last 300s 2>/dev/null | tail -5)
    
    if [ -n "$recent_activities" ]; then
        echo "$recent_activities"
    else
        log_warning "No recent activities found"
    fi
    
    echo ""
    log_info "Checking current Dynamic Island state..."
    local dynamic_island_state=$(xcrun simctl spawn booted log show --predicate '
        message CONTAINS "systemAperture" OR 
        message CONTAINS "preferredLayoutMode" OR
        message CONTAINS "compact" OR
        message CONTAINS "minimal"
    ' --info --last 120s 2>/dev/null | tail -3)
    
    if [ -n "$dynamic_island_state" ]; then
        echo "$dynamic_island_state"
    else
        log_warning "No Dynamic Island activity found"
    fi
}

# Monitor specific activity by ID
monitor_activity_by_id() {
    local activity_id="$1"
    local duration=${2:-15}
    
    if [ -z "$activity_id" ]; then
        log_error "Activity ID required"
        return 1
    fi
    
    echo_section "🎯 Monitoring Activity: $activity_id"
    
    run_with_timeout "$duration" xcrun simctl spawn booted log stream --predicate "
        message CONTAINS \"$activity_id\"
    " --info 2>/dev/null || true
}

# AlarmKit-specific debugging functions
monitor_alarm_lifecycle() {
    local duration=${1:-30}
    echo_section "⏰ Monitoring AlarmKit Lifecycle for ${duration} seconds"
    
    log_info "Watching for alarm scheduling, firing, and transitions..."
    log_info "Create an alarm in the app to see its full lifecycle!"
    
    # Focus on alarm lifecycle events
    run_with_timeout "$duration" xcrun simctl spawn booted log stream --predicate '
        (subsystem CONTAINS "AlarmKitCore" AND (
            message CONTAINS "schedule" OR
            message CONTAINS "Firing event" OR
            message CONTAINS "Transitioning" OR
            message CONTAINS "countdown to alert" OR
            message CONTAINS "Created activity" OR
            message CONTAINS "Updating activity"
        )) OR
        (subsystem CONTAINS "mobiletimerd" AND (
            message CONTAINS "firing alarmkit" OR
            message CONTAINS "timer alert" OR
            message CONTAINS "adding request"
        ))
    ' --info 2>/dev/null || true
    
    echo ""
    log_success "AlarmKit lifecycle monitoring completed"
}

# Check alarm authorization status
check_alarm_authorization() {
    echo_section "🔐 AlarmKit Authorization Status"
    
    log_info "Checking AlarmKit authorization for Calarm..."
    
    # Look for authorization-related logs
    local auth_logs=$(xcrun simctl spawn booted log show --predicate '
        subsystem CONTAINS "mobiletimerd" AND 
        message CONTAINS "Calarm" AND (
            message CONTAINS "authorized" OR
            message CONTAINS "denied" OR
            message CONTAINS "authorization"
        )
    ' --info --last 300s 2>/dev/null | tail -5)
    
    if [ -n "$auth_logs" ]; then
        echo "$auth_logs"
    else
        log_warning "No recent authorization logs found"
        log_info "Try creating an alarm to trigger authorization check"
    fi
}

# Debug alarm notifications
debug_alarm_notifications() {
    local duration=${1:-20}
    echo_section "🔔 Debugging Alarm Notifications for ${duration} seconds"
    
    log_info "Monitoring notification delivery and alert presentations..."
    log_info "Create an alarm and wait for it to fire!"
    
    # Focus on notification-related logs
    run_with_timeout "$duration" xcrun simctl spawn booted log stream --predicate '
        (subsystem CONTAINS "UserNotifications" AND (
            message CONTAINS "Calarm" OR
            message CONTAINS "alarmkit" OR
            message CONTAINS "timer"
        )) OR
        (process CONTAINS "SpringBoard" AND (
            message CONTAINS "alarm" OR
            message CONTAINS "notification" OR
            message CONTAINS "banner"
        )) OR
        (subsystem CONTAINS "mobiletimerd" AND (
            message CONTAINS "notification" OR
            message CONTAINS "alert" OR
            message CONTAINS "firing"
        ))
    ' --info 2>/dev/null || true
    
    echo ""
    log_success "Notification debugging completed"
}
#!/bin/bash

# Logging library for Greenplum Installer
# Provides consistent logging functions with colors and timestamps

# Colors for output
COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'

# Basic logging functions
log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2
    exit 1
}

# Enhanced logging with timestamps
log_info_with_timestamp() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${COLOR_BLUE}[INFO][${timestamp}]${COLOR_RESET} $1"
}

log_success_with_timestamp() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${COLOR_GREEN}[SUCCESS][${timestamp}]${COLOR_RESET} $1"
}

log_warn_with_timestamp() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${COLOR_YELLOW}[WARN][${timestamp}]${COLOR_RESET} $1"
}

log_error_with_timestamp() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${COLOR_RED}[ERROR][${timestamp}]${COLOR_RESET} $1" >&2
    exit 1
}

# Progress indicator functions
show_progress() {
    local message="$1"
    local current="$2"
    local total="$3"
    
    # Validate inputs are numbers
    if ! [[ "$current" =~ ^[0-9]+$ ]]; then
        current=0
    fi
    if ! [[ "$total" =~ ^[0-9]+$ ]] || [ "$total" -eq 0 ]; then
        total=1
    fi
    
    local percentage=$((current * 100 / total))
    
    printf "\r${COLOR_BLUE}[INFO]${COLOR_RESET} %s: [%-50s] %d%% (%d/%d)" \
        "$message" \
        "$(printf '#%.0s' $(seq 1 $((percentage / 2))))" \
        "$percentage" \
        "$current" \
        "$total"
}

show_spinner() {
    local message="$1"
    local pid=$2
    local delay=0.1
    local spinstr='|/-\'
    
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r${COLOR_BLUE}[INFO]${COLOR_RESET} %s [%c] " "$message" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r${COLOR_BLUE}[INFO]${COLOR_RESET} %s [Done]    \n" "$message"
}

# Progress tracking functions
CURRENT_PHASE=0
CURRENT_STEP=0

report_progress() {
    local phase_name="$1"
    local step_num="$2"
    local total_steps="$3"
    local step_desc="$4"
    
    echo "Phase $CURRENT_PHASE Step $step_num/$total_steps: $step_desc"
}

report_phase_start() {
    CURRENT_PHASE=$1
    CURRENT_STEP=0
    local phase_name="$2"
    echo ""
    echo "=== PHASE $CURRENT_PHASE: $phase_name ==="
}

report_phase_complete() {
    local phase_name="$1"
    echo "✓ PHASE $CURRENT_PHASE COMPLETED: $phase_name"
    echo ""
}

increment_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
}
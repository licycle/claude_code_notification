#!/bin/sh
# common.sh - Shared functions and variables for Claude Monitor installation
# This file is sourced by install.sh and other scripts

# ================= Configuration =================
APP_NAME="ClaudeMonitor"
INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
BINARY_PATH="$INSTALL_DIR/Contents/MacOS/$APP_NAME"
BASE_DIR="$HOME/.claude-hooks"
TRACKER_DIR="$BASE_DIR/task_tracker"
CONFIG_FILE="$BASE_DIR/config.sh"
API_MANAGER_SCRIPT="$BASE_DIR/api_manager.py"
ACCOUNT_MANAGER_SCRIPT="$BASE_DIR/account_manager.py"
PY_LOG="$BASE_DIR/python_debug.log"
SWIFT_LOG="$BASE_DIR/swift_debug.log"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ================= Utility Functions =================

cecho() {
    printf "%b\n" "$1"
}

# Get script directory (call from sourcing script)
get_script_dir() {
    cd "$(dirname "$0")" && pwd
}

# Check Python dependencies (no external dependencies required)
install_python_deps() {
    cecho "${YELLOW}Checking Python...${NC}"

    # Only check that Python 3 is available
    if ! command -v python3 >/dev/null 2>&1; then
        cecho "${RED}  Error: Python 3 is required but not installed.${NC}"
        return 1
    fi

    cecho "${GREEN}  ✓ Python 3 available${NC}"
    cecho "${GREEN}Python ready (no external dependencies required)${NC}"
}

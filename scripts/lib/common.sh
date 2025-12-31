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

# Check and install Python dependencies for workflow engine
install_python_deps() {
    cecho "${YELLOW}Checking Python dependencies...${NC}"

    # Check pyyaml (required for workflow YAML parsing)
    if ! python3 -c "import yaml" 2>/dev/null; then
        cecho "${YELLOW}  Installing pyyaml...${NC}"
        pip3 install --user pyyaml --quiet 2>/dev/null || {
            cecho "${RED}  Warning: Failed to install pyyaml. Workflow features may not work.${NC}"
        }
    else
        cecho "${GREEN}  ✓ pyyaml${NC}"
    fi

    # Check jinja2 (optional, has fallback)
    if ! python3 -c "import jinja2" 2>/dev/null; then
        cecho "${YELLOW}  Installing jinja2 (optional)...${NC}"
        pip3 install --user jinja2 --quiet 2>/dev/null || {
            cecho "${YELLOW}  Note: jinja2 not installed. Using simple template fallback.${NC}"
        }
    else
        cecho "${GREEN}  ✓ jinja2${NC}"
    fi

    cecho "${GREEN}Python dependencies ready${NC}"
}

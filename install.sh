#!/bin/sh
set -e

# ================= Source Libraries =================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/scripts/lib/common.sh"
. "$SCRIPT_DIR/scripts/lib/swift_build.sh"
. "$SCRIPT_DIR/scripts/lib/hooks_config.sh"
. "$SCRIPT_DIR/scripts/lib/shell_wrapper.sh"
. "$SCRIPT_DIR/scripts/lib/wizards.sh"
. "$SCRIPT_DIR/scripts/account_wizard.sh"

# ================= Quick Hooks Update Mode =================
if [ "$1" = "--hooks-only" ] || [ "$1" = "-p" ]; then
    cecho "${BLUE}=== Quick Hooks Update ===${NC}"

    TRACKER_SRC="$SCRIPT_DIR/python/task_tracker"

    if [ ! -d "$TRACKER_SRC" ]; then
        cecho "${RED}Error: Task Tracker source not found at $TRACKER_SRC${NC}"
        exit 1
    fi

    # Install Python dependencies
    install_python_deps

    # Check if database reset is requested
    if [ "$2" = "-r" ] || [ "$2" = "--reset-db" ]; then
        cecho "${YELLOW}Resetting database...${NC}"
        rm -f "$HOME/.claude-task-tracker/tasks.db"
    else
        cecho "${GREEN}Keeping existing database${NC}"
    fi

    # Use library function to install task tracker
    cecho "${YELLOW}Updating hook scripts and services...${NC}"
    install_task_tracker "$TRACKER_SRC" "$TRACKER_DIR"

    # Update shell wrapper (preserve existing aliases)
    cecho "${YELLOW}Updating shell wrapper...${NC}"
    update_shell_wrapper_preserve_aliases "$CONFIG_FILE"

    # Update slash commands
    cecho "${YELLOW}Updating slash commands...${NC}"
    COMMANDS_SRC="$SCRIPT_DIR/commands"
    COMMANDS_DEST="$HOME/.claude/commands"
    mkdir -p "$COMMANDS_DEST"
    if [ -d "$COMMANDS_SRC" ]; then
        for cmd_file in "$COMMANDS_SRC"/*.md; do
            [ -f "$cmd_file" ] && cp "$cmd_file" "$COMMANDS_DEST/"
        done
    fi

    cecho "${GREEN}Hooks updated${NC}"
    cecho "   Source: ${BLUE}$TRACKER_SRC${NC}"
    cecho "   Target: ${BLUE}$TRACKER_DIR${NC}"
    exit 0
fi

# ================= Quick App Rebuild Mode =================
if [ "$1" = "--app-only" ] || [ "$1" = "-a" ]; then
    cecho "${BLUE}=== Quick App Rebuild ===${NC}"

    # Kill existing app
    cecho "${YELLOW}Stopping existing processes...${NC}"
    pkill -9 -f "$APP_NAME" 2>/dev/null || true
    sleep 1

    if pgrep -f "$APP_NAME" >/dev/null 2>&1; then
        cecho "${YELLOW}Process still running, retrying...${NC}"
        pkill -9 -f "$APP_NAME" 2>/dev/null || true
        sleep 1
    fi

    # Prepare directories
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/Contents/MacOS"
    mkdir -p "$INSTALL_DIR/Contents/Resources"

    # Use library functions
    SWIFT_DIR="$SCRIPT_DIR/swift"
    ASSETS_DIR="$SCRIPT_DIR/assets"

    cecho "${YELLOW}Compiling Swift...${NC}"
    compile_swift "$SWIFT_DIR" "$BINARY_PATH"
    copy_app_icons "$ASSETS_DIR" "$INSTALL_DIR"
    create_info_plist "$INSTALL_DIR" "$APP_NAME"
    sign_and_register_app "$INSTALL_DIR" "$APP_NAME"

    # Verify installation
    if [ -x "$BINARY_PATH" ]; then
        cecho "${GREEN}App rebuilt and installed${NC}"
        cecho "   Binary: ${GREEN}$BINARY_PATH${NC}"
        cecho "   Test:   ${GREEN}$BINARY_PATH gui${NC}"
    else
        cecho "${RED}Installation failed - binary not found${NC}"
        exit 1
    fi
    exit 0
fi

cecho "${BLUE}=== Claude Monitor Pro Installer ===${NC}"

# ================= 0. Cleanup Old Versions =================
if [ -d "$INSTALL_DIR" ]; then
    cecho "${YELLOW}[!] Cleaning up previous installation...${NC}"
    rm -rf "$INSTALL_DIR"
fi
rm -f "$PY_LOG" "$SWIFT_LOG"
mkdir -p "$BASE_DIR"

# ================= 1. Build Swift Core Application =================
cecho "${YELLOW}[1/7] Compiling Swift Core...${NC}"
mkdir -p "$INSTALL_DIR/Contents/MacOS"
mkdir -p "$INSTALL_DIR/Contents/Resources"

SWIFT_DIR="$SCRIPT_DIR/swift"
ASSETS_DIR="$SCRIPT_DIR/assets"

compile_swift "$SWIFT_DIR" "$BINARY_PATH"
copy_app_icons "$ASSETS_DIR" "$INSTALL_DIR"
create_info_plist "$INSTALL_DIR" "$APP_NAME"
cecho "${GREEN}Swift Core compiled${NC}"

# ================= 2. Registration & Signing =================
cecho "${YELLOW}[2/7] Signing and Registering App...${NC}"
sign_and_register_app "$INSTALL_DIR" "$APP_NAME"
cecho "${GREEN}App Registered with macOS Notification Center${NC}"

# ================= 3. Install Scripts =================
cecho "${YELLOW}[3/7] Installing Managers...${NC}"
CLI_SRC="$SCRIPT_DIR/python/task_tracker/cli"
install_cli_scripts "$CLI_SRC" "$BASE_DIR"

# ================= 3.5 Task Tracker Installation =================
cecho "\n${BLUE}--- Installing Task Tracker ---${NC}"

# Check Python is available
install_python_deps

TRACKER_SRC="$SCRIPT_DIR/python/task_tracker"
install_task_tracker "$TRACKER_SRC" "$TRACKER_DIR"

# Summary config is stored in ~/.claude-task-tracker/ (shared with Swift/Python)
SUMMARY_CONFIG_DIR="$HOME/.claude-task-tracker"
mkdir -p "$SUMMARY_CONFIG_DIR"
run_summary_wizard "$SUMMARY_CONFIG_DIR/config.json"

# ================= 3.6 Install Slash Commands =================
cecho "\n${BLUE}--- Installing Slash Commands ---${NC}"
COMMANDS_SRC="$SCRIPT_DIR/commands"
COMMANDS_DEST="$HOME/.claude/commands"
mkdir -p "$COMMANDS_DEST"

if [ -d "$COMMANDS_SRC" ]; then
    for cmd_file in "$COMMANDS_SRC"/*.md; do
        if [ -f "$cmd_file" ]; then
            cmd_name=$(basename "$cmd_file")
            cp "$cmd_file" "$COMMANDS_DEST/$cmd_name"
            cecho "   Installed: ${GREEN}/$(basename "$cmd_name" .md)${NC}"
        fi
    done
    cecho "${GREEN}Slash commands installed${NC}"
else
    cecho "${YELLOW}No slash commands found in $COMMANDS_SRC${NC}"
fi

# ================= Generate Shell Config =================
cecho "${YELLOW}Generating Shell Integration...${NC}"
generate_shell_wrapper "$CONFIG_FILE" "$BINARY_PATH" "$API_MANAGER_SCRIPT" "$ACCOUNT_MANAGER_SCRIPT" "$BASE_DIR"

# ================= 4. Account Setup =================
cecho "${YELLOW}[4/7] Setting up Claude accounts...${NC}"
run_account_wizard
append_account_aliases "$CONFIG_FILE" "$account_aliases" "$account_paths"
first_alias=$(echo "$account_aliases" | awk '{print $1}')
first_alias=${first_alias:-c}

# ================= 5. API Profiles Setup =================
run_api_wizard

# ================= 6. Configure Claude Hooks Integration =================
cecho "\n${YELLOW}[6/7] Configuring Claude Hooks...${NC}"
configure_hooks_for_accounts "$account_aliases" "$account_paths"

# ================= 7. Finalize =================
cecho "\n${YELLOW}[7/7] Configuring Shell Integration...${NC}"
RC_FILE="$HOME/.zshrc"
[ -f "$HOME/.bashrc" ] && RC_FILE="$HOME/.bashrc"
update_shell_rc "$CONFIG_FILE"
cecho "${GREEN}Shell configuration updated${NC}"

[ -z "$first_alias" ] && first_alias="c"

# ================= Summary =================
print_installation_summary "$account_aliases" "$account_paths" "$first_alias" "$RC_FILE" "$BINARY_PATH"
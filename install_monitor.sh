#!/bin/sh
set -e

# ================= Configuration =================
APP_NAME="ClaudeMonitor"
INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
BINARY_PATH="$INSTALL_DIR/Contents/MacOS/$APP_NAME"
BASE_DIR="$HOME/.claude-hooks"
CONFIG_FILE="$BASE_DIR/config.sh"
PY_LOG="$BASE_DIR/python_debug.log"
SWIFT_LOG="$BASE_DIR/swift_debug.log"

# Get script directory (where source files are located)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors (use printf for proper rendering)
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Helper function for colored output
cecho() {
    printf "%b\n" "$1"
}

cecho "${BLUE}=== Claude Monitor Pro Installer (English Version) ===${NC}"

# ================= 0. Cleanup Old Versions =================
if [ -d "$INSTALL_DIR" ]; then
    cecho "${YELLOW}[!] Cleaning up previous installation...${NC}"
    rm -rf "$INSTALL_DIR"
fi
# Clear old logs for a fresh start
rm -f "$PY_LOG" "$SWIFT_LOG"
mkdir -p "$BASE_DIR"

# ================= 1. Build Swift Core Application =================
cecho "${YELLOW}[1/6] Compiling Swift Core (Minimize-Restore Fix)...${NC}"
mkdir -p "$INSTALL_DIR/Contents/MacOS"

# Check if Swift source files exist
SWIFT_DIR="$SCRIPT_DIR/swift"
SWIFT_FILES="Logger.swift PermissionManager.swift AppDelegate.swift SettingsWindow.swift Main.swift"

for swiftfile in $SWIFT_FILES; do
    if [ ! -f "$SWIFT_DIR/$swiftfile" ]; then
        cecho "${RED}❌ Error: $swiftfile not found in $SWIFT_DIR${NC}"
        exit 1
    fi
done

# Compile Swift from source files
swiftc \
    "$SWIFT_DIR/Logger.swift" \
    "$SWIFT_DIR/PermissionManager.swift" \
    "$SWIFT_DIR/AppDelegate.swift" \
    "$SWIFT_DIR/SettingsWindow.swift" \
    "$SWIFT_DIR/Main.swift" \
    -o "$BINARY_PATH" \
    -target arm64-apple-macosx12.0
chmod +x "$BINARY_PATH"

# Create Info.plist (Required for Notifications and Automation)
cat << EOF > "$INSTALL_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.custom.claude.monitor</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>ClaudeMonitor needs automation access to restore minimized windows when you click notifications.</string>
</dict>
</plist>
EOF

# ================= 2. Registration & Signing =================
cecho "${YELLOW}[2/6] Signing and Registering App...${NC}"
# Ad-hoc signing to let macOS trust the binary
codesign --force --deep --sign - "$INSTALL_DIR"
# Force-run to register with LaunchServices (Fixes "Notification not showing" issue)
open "$INSTALL_DIR"
sleep 0.5
pkill -f "$APP_NAME" || true

cecho "${GREEN}✅ App Registered with macOS Notification Center${NC}"

# ================= 3. Install Python Hooks =================
cecho "${YELLOW}[3/6] Deploying Hook Logic...${NC}"

# Check if Python source files exist
for pyfile in hook.py notification_hook.py stop_hook.py; do
    if [ ! -f "$SCRIPT_DIR/python/$pyfile" ]; then
        cecho "${RED}❌ Error: $pyfile not found in $SCRIPT_DIR/python/${NC}"
        exit 1
    fi
done

# Copy Python hooks to destination
cp "$SCRIPT_DIR/python/hook.py" "$BASE_DIR/hook.py"
cp "$SCRIPT_DIR/python/notification_hook.py" "$BASE_DIR/notification_hook.py"
cp "$SCRIPT_DIR/python/stop_hook.py" "$BASE_DIR/stop_hook.py"

# Make them executable
chmod +x "$BASE_DIR/hook.py"
chmod +x "$BASE_DIR/notification_hook.py"
chmod +x "$BASE_DIR/stop_hook.py"

cecho "${GREEN}✅ Python hooks installed${NC}"

# Function to generate hooks configuration in settings.json for Claude Code integration
generate_hooks_config() {
    local config_dir=$1
    local settings_file="$config_dir/settings.json"
    local hook_script_abs="$HOME/.claude-hooks/notification_hook.py"
    local stop_hook_abs="$HOME/.claude-hooks/stop_hook.py"

    mkdir -p "$config_dir"

    # Use Python to safely merge hooks into settings.json (handles both new and existing files)
    SETTINGS_FILE="$settings_file" \
    HOOK_SCRIPT="$hook_script_abs" \
    STOP_HOOK="$stop_hook_abs" \
    python3 << 'PYEOF'
import os
import json

settings_file = os.environ['SETTINGS_FILE']
hook_script = os.environ['HOOK_SCRIPT']
stop_hook = os.environ['STOP_HOOK']

# Define hooks configuration
hooks_config = {
    "Notification": [
        {
            "matcher": "idle_prompt",
            "hooks": [{"type": "command", "command": hook_script, "timeout": 10}]
        },
        {
            "matcher": "permission_prompt",
            "hooks": [{"type": "command", "command": hook_script, "timeout": 10}]
        },
        {
            "matcher": "elicitation_dialog",
            "hooks": [{"type": "command", "command": hook_script, "timeout": 10}]
        },
        {
            "matcher": "auth_success",
            "hooks": [{"type": "command", "command": hook_script, "timeout": 10}]
        },
        {
            "matcher": "",
            "hooks": [{"type": "command", "command": hook_script, "timeout": 10}]
        }
    ],
    "Stop": [
        {
            "hooks": [{"type": "command", "command": stop_hook, "timeout": 15}]
        }
    ]
}

try:
    # Load existing settings or create new
    if os.path.exists(settings_file):
        with open(settings_file, 'r') as f:
            settings = json.load(f)
        action = "Updated"
    else:
        settings = {"$schema": "https://json.schemastore.org/claude-code-settings.json"}
        action = "Created"

    # Merge hooks config
    settings['hooks'] = hooks_config

    # Write back
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)

    print(f"✅ {action} hooks configuration in {settings_file}")
    exit(0)
except Exception as e:
    print(f"❌ Error: {e}")
    exit(1)
PYEOF

    return $?
}

# ================= 4. Account Configuration Wizard =================
cecho "${YELLOW}[4/6] Setting up Claude accounts...${NC}"

# ================= Auto-detect Existing Accounts =================
# Use space-separated lists instead of associative arrays (sh compatible)
account_aliases=""
account_paths=""

if [ -f "$CONFIG_FILE" ]; then
    cecho "${YELLOW}[!] Detected existing configuration${NC}"
    # Parse existing aliases from config.sh
    while IFS= read -r line; do
        case "$line" in
            alias\ *=\'_claude_wrapper*)
                # Extract alias name and path (trim spaces)
                alias_name=$(echo "$line" | sed 's/alias[[:space:]]*\([^=]*\)=.*/\1/' | tr -d ' ')
                config_path=$(echo "$line" | sed "s/.*_claude_wrapper \"\([^\"]*\)\".*/\1/")
                account_aliases="${account_aliases:+$account_aliases }$alias_name"
                account_paths="$account_paths|$config_path"
                cecho "  Found: ${GREEN}$alias_name${NC} -> $config_path"
                ;;
        esac
    done < "$CONFIG_FILE"
fi

# Interactive Wizard
cecho "\n${BLUE}--- Account Setup Wizard ---${NC}"

# Check if default account already exists
has_default=0
if echo "$account_aliases" | grep -q " c"; then
    has_default=1
    cecho "DEFAULT account ${GREEN}'c'${NC} already configured"
    printf "Keep it? [Y/n]: "
    read keep_default
    keep_default=${keep_default:-Y}
    if [ "$keep_default" = "n" ] || [ "$keep_default" = "N" ]; then
        # Remove 'c' from lists
        account_aliases=$(echo "$account_aliases" | sed 's/ c//')
        # Remove corresponding path (this is tricky, for now just rebuild)
        has_default=0
    fi
fi

if [ $has_default -eq 0 ]; then
    printf "Enter alias for DEFAULT account (default 'c'): "
    read def_alias
    def_alias=${def_alias:-c}
    # Add to lists if not exists
    if ! echo " $account_aliases " | grep -q " $def_alias "; then
        account_aliases="${account_aliases:+$account_aliases }$def_alias"
        account_paths="${account_paths}|$HOME/.claude"
    fi
else
    def_alias="c"
fi

# Track additional account config paths for hooks.json installation
additional_configs=""

while true; do
    printf "Add another account? (y/n): "
    read yn
    case $yn in
        [Yy]* )
            # Input alias with validation
            while true; do
                printf "Alias Name (e.g. cw): "
                read a_alias
                if [ -z "$a_alias" ]; then
                    cecho "${RED}❌ Alias name cannot be empty${NC}"
                    continue
                fi
                if echo "$account_aliases" | grep -q " $a_alias"; then
                    cecho "${YELLOW}⚠️  Alias '$a_alias' already exists${NC}"
                    printf "Overwrite? (y/n): "
                    read overwrite
                    if [ "$overwrite" = "y" ] || [ "$overwrite" = "Y" ]; then
                        # Remove old entry
                        account_aliases=$(echo "$account_aliases" | sed "s/ $a_alias//")
                        break
                    fi
                else
                    break
                fi
            done

            # Input config path with validation
            while true; do
                printf "Config Path (e.g. ~/.claude-work): "
                read a_path
                if [ -z "$a_path" ]; then
                    cecho "${RED}❌ Config path cannot be empty${NC}"
                    continue
                fi
                # Expand tilde manually
                case "$a_path" in
                    \~/*) a_path_expanded="$HOME${a_path#\~}" ;;
                    *) a_path_expanded="$a_path" ;;
                esac
                # Confirm if path doesn't exist
                if [ ! -d "$a_path_expanded" ]; then
                    cecho "${YELLOW}⚠️  Path does not exist: $a_path_expanded${NC}"
                    printf "Create it? (y/n): "
                    read create_dir
                    if [ "$create_dir" = "y" ] || [ "$create_dir" = "Y" ]; then
                        mkdir -p "$a_path_expanded"
                        cecho "${GREEN}✅ Created directory${NC}"
                        break
                    fi
                else
                    break
                fi
            done

            account_aliases="${account_aliases:+$account_aliases }$a_alias"
            account_paths="$account_paths|$a_path_expanded"
            additional_configs="${additional_configs:+$additional_configs }$a_path_expanded"
            cecho "${GREEN}✅ Added: $a_alias -> $a_path_expanded${NC}"
            ;;
        * ) break;;
    esac
done

# ================= Write Final Configuration =================
cecho "\n${YELLOW}Writing configuration...${NC}"

# Rebuild config.sh from account lists
cat << 'EOF' > "$CONFIG_FILE"
# Claude Monitor Configuration File
# Auto-generated by install script

_CLAUDE_MON_APP="$HOME/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor"
_CLAUDE_HOOK_PY="$HOME/.claude-hooks/hook.py"

# --- Core Wrapper Function ---
_claude_wrapper() {
    config_path="$1"
    shift 1

    # 1. [Detector] Capture current Terminal Bundle ID, PID and CGWindowID
    # Output format: "bundleID|PID|CGWindowID"
    detected_info=$("$_CLAUDE_MON_APP" detect 2>/dev/null)
    detected_bundle=$(echo "$detected_info" | cut -d'|' -f1)
    detected_pid=$(echo "$detected_info" | cut -d'|' -f2)
    detected_window_id=$(echo "$detected_info" | cut -d'|' -f3)

    # 2. Extract account alias from config path
    # ~/.claude -> default, ~/.claude-work -> work
    config_basename=$(basename "$config_path")
    if [ "$config_basename" = ".claude" ]; then
        account_alias="default"
    else
        account_alias=$(echo "$config_basename" | sed 's/^\.claude-//')
    fi

    # 3. Inject Environment Variables
    export CLAUDE_TERM_BUNDLE_ID="${detected_bundle:-com.apple.Terminal}"
    export CLAUDE_TERM_PID="${detected_pid:-0}"
    export CLAUDE_CG_WINDOW_ID="${detected_window_id:-0}"
    export CLAUDE_CONFIG_DIR="$config_path"
    export CLAUDE_ACCOUNT_ALIAS="$account_alias"

    # 4. Run Claude directly
    # Note: Rate limit detection is now handled via Stop hook in settings.json
    command claude "$@"
}

# --- User Aliases ---
EOF

# Write all accounts - simple iteration
count=0
for alias_name in $account_aliases; do
    [ -z "$alias_name" ] && continue
    count=$((count + 1))

    # Extract the count-th path from account_paths
    IFS='|'
    idx=0
    for path in $account_paths; do
        idx=$((idx + 1))
        if [ $idx -eq $((count + 1)) ]; then  # +1 because paths start with |
            echo "alias $alias_name='_claude_wrapper \"$path\"'" >> "$CONFIG_FILE"
            break
        fi
    done
    IFS=' '
done

cecho "${GREEN}✅ Configuration file updated with $count account(s)${NC}"

# ================= 5. Configure Claude Hooks Integration =================
cecho "\n${BLUE}--- Claude Hooks Integration ---${NC}"
echo "This will enable real-time notifications (idle alerts, permission prompts, etc.)"
echo ""

# Install hooks configuration in settings.json for all configured accounts
idx=0
for alias_name in $account_aliases; do
    [ -z "$alias_name" ] && continue
    idx=$((idx + 1))

    # Extract the idx-th path from account_paths
    IFS='|'
    path_idx=0
    config_path=""
    for path in $account_paths; do
        path_idx=$((path_idx + 1))
        if [ $path_idx -eq $((idx + 1)) ]; then  # +1 because paths start with |
            config_path="$path"
            break
        fi
    done
    IFS=' '

    [ -z "$config_path" ] && continue

    # Check if settings.json already exists
    if [ -f "$config_path/settings.json" ]; then
        cecho "${YELLOW}[!] settings.json already exists for '$alias_name' ($config_path)${NC}"
        cecho "${BLUE}Will show you the hooks config to manually merge${NC}"
    fi

    printf "Configure hooks for '$alias_name' ($config_path)? [Y/n]: "
    read install_hook
    install_hook=${install_hook:-Y}
    if [ "$install_hook" = "Y" ] || [ "$install_hook" = "y" ] || [ -z "$install_hook" ]; then
        generate_hooks_config "$config_path"
    fi
done

# ================= 6. Inject into Shell RC =================
cecho "\n${YELLOW}[6/6] Configuring Shell Integration...${NC}"

RC_FILE="$HOME/.zshrc"
[ -f "$HOME/.bashrc" ] && RC_FILE="$HOME/.bashrc"

SOURCE_CMD="source \"$CONFIG_FILE\""

# Clean up any duplicate/malformed entries first
if grep -q "Claude Monitor" "$RC_FILE"; then
    cecho "${YELLOW}[!] Cleaning up existing Claude Monitor entries...${NC}"
    # Create temporary file without Claude Monitor sections
    grep -v "Claude Monitor" "$RC_FILE" | grep -v "$CONFIG_FILE" > "${RC_FILE}.tmp"
    mv "${RC_FILE}.tmp" "$RC_FILE"
fi

# Add fresh configuration
echo "" >> "$RC_FILE"
echo "# Claude Monitor Hooks" >> "$RC_FILE"
echo "$SOURCE_CMD" >> "$RC_FILE"
cecho "${GREEN}✅ Shell configuration updated${NC}"

# ================= Summary =================
cecho "\n${GREEN}╔═══════════════════════════════════════════════╗${NC}"
cecho "${GREEN}║     🎉 Installation Complete! 🎉             ║${NC}"
cecho "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
cecho "${BLUE}📋 Configured Accounts:${NC}"
idx=0
for alias_name in $account_aliases; do
    [ -z "$alias_name" ] && continue
    idx=$((idx + 1))

    # Extract the idx-th path
    IFS='|'
    path_idx=0
    for path in $account_paths; do
        path_idx=$((path_idx + 1))
        if [ $path_idx -eq $((idx + 1)) ]; then
            cecho "   ${GREEN}$alias_name${NC} → $path"
            break
        fi
    done
    IFS=' '
done
echo ""
cecho "${YELLOW}📝 Next Steps:${NC}"
cecho "   1. Run: ${GREEN}source $RC_FILE${NC}"
cecho "   2. Test: ${GREEN}$def_alias${NC} (or any configured alias)"
cecho "   3. Settings: ${GREEN}$BINARY_PATH gui${NC}"
cecho "   4. Logs: ${BLUE}~/.claude-hooks/${NC}"
echo ""
cecho "${YELLOW}⚠️  Automation Permission (for minimized window restore):${NC}"
cecho "   If notification click doesn't restore minimized windows:"
cecho "   ${BLUE}System Preferences > Privacy & Security > Privacy > Automation${NC}"
cecho "   Allow ${GREEN}ClaudeMonitor${NC} to control ${GREEN}System Events${NC}"
echo ""
cecho "${BLUE}💡 Tip: Run this script again to add/modify accounts${NC}"

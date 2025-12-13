#!/bin/sh
set -e

# ================= Configuration =================
APP_NAME="ClaudeMonitor"
INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
BINARY_PATH="$INSTALL_DIR/Contents/MacOS/$APP_NAME"
BASE_DIR="$HOME/.claude-hooks"
CONFIG_FILE="$BASE_DIR/config.sh"
API_MANAGER_SCRIPT="$BASE_DIR/api_manager.py"
ACCOUNT_MANAGER_SCRIPT="$BASE_DIR/account_manager.py"
PY_LOG="$BASE_DIR/python_debug.log"
SWIFT_LOG="$BASE_DIR/swift_debug.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cecho() { printf "%b\n" "$1"; }

# Function to generate hooks configuration in settings.json
generate_hooks_config() {
    local config_dir=$1
    local settings_file="$config_dir/settings.json"
    local hook_script_abs="$HOME/.claude-hooks/notification_hook.py"
    local stop_hook_abs="$HOME/.claude-hooks/stop_hook.py"

    mkdir -p "$config_dir"

    SETTINGS_FILE="$settings_file" \
    HOOK_SCRIPT="$hook_script_abs" \
    STOP_HOOK="$stop_hook_abs" \
    python3 << 'PYEOF'
import os, json

settings_file = os.environ['SETTINGS_FILE']
hook_script = os.environ['HOOK_SCRIPT']
stop_hook = os.environ['STOP_HOOK']

hooks_config = {
    "Notification": [
        {"matcher": "idle_prompt", "hooks": [{"type": "command", "command": hook_script, "timeout": 10}]},
        {"matcher": "permission_prompt", "hooks": [{"type": "command", "command": hook_script, "timeout": 10}]},
        {"matcher": "elicitation_dialog", "hooks": [{"type": "command", "command": hook_script, "timeout": 10}]},
        {"matcher": "auth_success", "hooks": [{"type": "command", "command": hook_script, "timeout": 10}]},
        {"matcher": "", "hooks": [{"type": "command", "command": hook_script, "timeout": 10}]}
    ],
    "Stop": [{"hooks": [{"type": "command", "command": stop_hook, "timeout": 15}]}]
}

try:
    settings = json.load(open(settings_file)) if os.path.exists(settings_file) else {"$schema": "https://json.schemastore.org/claude-code-settings.json"}
    settings['hooks'] = hooks_config
    json.dump(settings, open(settings_file, 'w'), indent=2)
    print(f"✅ Hooks configured in {settings_file}")
except Exception as e:
    print(f"❌ Error: {e}")
    exit(1)
PYEOF
    return $?
}

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

SWIFT_DIR="$SCRIPT_DIR/swift"
SWIFT_FILES="Logger.swift PermissionManager.swift AppDelegate.swift SettingsWindow.swift Main.swift"

for swiftfile in $SWIFT_FILES; do
    if [ ! -f "$SWIFT_DIR/$swiftfile" ]; then
        cecho "${RED}Error: $swiftfile not found in $SWIFT_DIR${NC}"
        exit 1
    fi
done

swiftc \
    "$SWIFT_DIR/Logger.swift" \
    "$SWIFT_DIR/PermissionManager.swift" \
    "$SWIFT_DIR/AppDelegate.swift" \
    "$SWIFT_DIR/SettingsWindow.swift" \
    "$SWIFT_DIR/Main.swift" \
    -o "$BINARY_PATH" \
    -target arm64-apple-macosx12.0
chmod +x "$BINARY_PATH"

# Create Info.plist
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
    <string>ClaudeMonitor needs automation access to restore minimized windows.</string>
</dict>
</plist>
EOF

cecho "${GREEN}✅ Swift Core compiled${NC}"

# ================= 2. Registration & Signing =================
cecho "${YELLOW}[2/7] Signing and Registering App...${NC}"
codesign --force --deep --sign - "$INSTALL_DIR"
open "$INSTALL_DIR"
sleep 0.5
pkill -f "$APP_NAME" || true
cecho "${GREEN}✅ App Registered with macOS Notification Center${NC}"

# ================= 3. Install Scripts =================
cecho "${YELLOW}[3/7] Installing Managers...${NC}"

if [ ! -f "$SCRIPT_DIR/api_manager.py" ] || [ ! -f "$SCRIPT_DIR/account_wizard.sh" ] || [ ! -f "$SCRIPT_DIR/account_manager.py" ]; then
    cecho "${RED}❌ Missing dependency files (api_manager.py, account_manager.py or account_wizard.sh).${NC}"
    exit 1
fi

cp "$SCRIPT_DIR/hook.py" "$BASE_DIR/hook.py" 2>/dev/null || true
cp "$SCRIPT_DIR/notification_hook.py" "$BASE_DIR/notification_hook.py" 2>/dev/null || true
cp "$SCRIPT_DIR/stop_hook.py" "$BASE_DIR/stop_hook.py" 2>/dev/null || true
cp "$SCRIPT_DIR/api_manager.py" "$API_MANAGER_SCRIPT"
cp "$SCRIPT_DIR/account_manager.py" "$ACCOUNT_MANAGER_SCRIPT"

chmod +x "$BASE_DIR/"*.py
cecho "${GREEN}✅ Scripts installed${NC}"

# ================= Generate Shell Config =================
cecho "${YELLOW}Generating Shell Integration...${NC}"

cat << EOF > "$CONFIG_FILE"
# Claude Monitor Configuration
# Auto-generated by install.sh

_CLAUDE_MON_APP="$BINARY_PATH"
_CLAUDE_API_MANAGER="$API_MANAGER_SCRIPT"
_CLAUDE_ACCOUNT_MANAGER="$ACCOUNT_MANAGER_SCRIPT"

# --- API Management Command ---
function claude-api() {
    python3 "\$_CLAUDE_API_MANAGER" "\$@"
}

# --- Account Management Command ---
function claude-ac() {
    python3 "\$_CLAUDE_ACCOUNT_MANAGER" "\$@"
    if [ "\$1" = "add" ] || [ "\$1" = "rm" ]; then
        echo "💡 Run: source ~/.zshrc to apply changes"
    fi
}

# --- Core Smart Wrapper ---
_claude_wrapper() {
    local config_path="\$1"
    shift 1

    # 1. Detect Window IMMEDIATELY (before any processing)
    local detected_info=\$("\$_CLAUDE_MON_APP" detect 2>/dev/null)
    local detected_bundle=\$(echo "\$detected_info" | cut -d'|' -f1)
    local detected_pid=\$(echo "\$detected_info" | cut -d'|' -f2)
    local detected_window_id=\$(echo "\$detected_info" | cut -d'|' -f3)

    # 2. Extract account alias from config path
    local config_basename=\$(basename "\$config_path")
    local account_alias
    if [ "\$config_basename" = ".claude" ]; then
        account_alias="default"
    else
        account_alias=\$(echo "\$config_basename" | sed 's/^\\.claude-//')
    fi

    # 3. Parse Arguments
    local -a claude_args
    local api_profile=""

    while [[ \$# -gt 0 ]]; do
        key="\$1"
        case \$key in
            --api)
                api_profile="\$2"
                shift 2
                ;;
            --api=*)
                api_profile="\${key#*=}"
                shift 1
                ;;
            *)
                claude_args+=("\$1")
                shift 1
                ;;
        esac
    done

    # 4. Execute in Subshell (API env isolation only)
    (
        if [ -n "\$api_profile" ]; then
            eval "\$(python3 "\$_CLAUDE_API_MANAGER" get-env "\$api_profile")"
            echo "🚀 API Profile Active: \$api_profile"
        fi

        export CLAUDE_TERM_BUNDLE_ID="\${detected_bundle:-com.apple.Terminal}"
        export CLAUDE_TERM_PID="\${detected_pid:-0}"
        export CLAUDE_CG_WINDOW_ID="\${detected_window_id:-0}"
        export CLAUDE_CONFIG_DIR="\$config_path"
        export CLAUDE_ACCOUNT_ALIAS="\$account_alias"

        command claude "\${claude_args[@]}"
    )
}
EOF

# ================= 4. Account Setup =================
cecho "${YELLOW}[4/7] Running Account Wizard...${NC}"
chmod +x "$SCRIPT_DIR/account_wizard.sh"
"$SCRIPT_DIR/account_wizard.sh"

TEMP_ACCOUNTS="/tmp/claude_new_accounts.txt"
first_alias="" # To store one for usage example

if [ -f "$TEMP_ACCOUNTS" ]; then
    # Sync accounts to accounts.json for claude-ac command
    ACCOUNTS_JSON="$BASE_DIR/accounts.json"
    echo "{" > "$ACCOUNTS_JSON"
    first_json=true

    while IFS='|' read -r alias_name path; do
        if [ -n "$alias_name" ]; then
            echo "alias $alias_name='_claude_wrapper \"$path\"'" >> "$CONFIG_FILE"
            cecho "   Registered: $alias_name"
            if [ -z "$first_alias" ]; then first_alias="$alias_name"; fi

            # Add to accounts.json
            if [ "$first_json" = true ]; then
                first_json=false
            else
                echo "," >> "$ACCOUNTS_JSON"
            fi
            printf '  "%s": "%s"' "$alias_name" "$path" >> "$ACCOUNTS_JSON"
        fi
    done < "$TEMP_ACCOUNTS"

    echo "" >> "$ACCOUNTS_JSON"
    echo "}" >> "$ACCOUNTS_JSON"
    # Note: Don't delete TEMP_ACCOUNTS yet, needed for hooks configuration
fi

# ================= 5. API Profiles Setup =================
cecho "\n${BLUE}--- API Profiles Setup ---${NC}"
cecho "Add API profiles for third-party providers (Kimi, Qwen, DeepSeek, etc.)"
cecho "Usage: ${GREEN}c --api <profile_name>${NC}"
echo ""

while true; do
    printf "Add an API profile? (y/N): "
    read setup_api
    case $setup_api in
        [Yy]* ) ;;
        * ) break;;
    esac

    printf "Profile Name (e.g. kimi, qwen): "
    read api_name
    [ -z "$api_name" ] && continue

    env_vars=""

    # === Standard Environment Variables (prompt for values directly) ===
    cecho "\n${YELLOW}=== Standard Environment Variables ===${NC}"

    printf "  ANTHROPIC_BASE_URL (API endpoint): "
    read val_url
    [ -n "$val_url" ] && env_vars="$env_vars ANTHROPIC_BASE_URL=$val_url"

    printf "  ANTHROPIC_API_KEY (API key): "
    read val_key
    [ -n "$val_key" ] && env_vars="$env_vars ANTHROPIC_API_KEY=$val_key"

    printf "  ANTHROPIC_MODEL (model name, optional): "
    read val_model
    [ -n "$val_model" ] && env_vars="$env_vars ANTHROPIC_MODEL=$val_model"

    # === Custom Environment Variables ===
    cecho "\n${YELLOW}=== Custom Environment Variables (optional) ===${NC}"
    cecho "Format: ${GREEN}KEY=VALUE${NC}, type ${GREEN}done${NC} to finish"

    while true; do
        printf "  > "
        read env_input
        case $env_input in
            done|DONE|Done) break;;
            *=*) env_vars="$env_vars $env_input";;
            "") break;;
            *) cecho "${RED}  Invalid format. Use KEY=VALUE or 'done'${NC}";;
        esac
    done

    if [ -n "$env_vars" ]; then
        python3 "$API_MANAGER_SCRIPT" add "$api_name" $env_vars
    else
        cecho "${YELLOW}No variables added for $api_name${NC}"
    fi
done

# ================= 6. Configure Claude Hooks Integration =================
cecho "\n${YELLOW}[6/7] Configuring Claude Hooks...${NC}"

if [ -f "$TEMP_ACCOUNTS" ]; then
    while IFS='|' read -r alias_name path; do
        if [ -n "$path" ]; then
            printf "Configure hooks for '$alias_name' ($path)? [Y/n]: "
            read install_hook
            install_hook=${install_hook:-Y}
            if [ "$install_hook" = "Y" ] || [ "$install_hook" = "y" ]; then
                generate_hooks_config "$path"
            fi
        fi
    done < "$TEMP_ACCOUNTS"
    rm -f "$TEMP_ACCOUNTS"
fi

# ================= 7. Finalize =================
cecho "\n${YELLOW}[7/7] Configuring Shell Integration...${NC}"
RC_FILE="$HOME/.zshrc"
SOURCE_CMD="source \"$CONFIG_FILE\""
if ! grep -q "$CONFIG_FILE" "$RC_FILE"; then
    echo "" >> "$RC_FILE"
    echo "$SOURCE_CMD" >> "$RC_FILE"
fi

[ -z "$first_alias" ] && first_alias="c"

cecho "\n${GREEN}🎉 Installation Complete!${NC}"
cecho ""
cecho "${BLUE}📋 Usage:${NC}"
cecho "  1. Reload shell: ${GREEN}source ~/.zshrc${NC}"
cecho "  2. Run Account:  ${GREEN}$first_alias${NC}"
cecho "  3. Use API:      ${GREEN}$first_alias --api kimi${NC}"
cecho ""
cecho "${BLUE}📋 Management Commands:${NC}"
cecho "  ${GREEN}claude-api list${NC}      - List all API profiles"
cecho "  ${GREEN}claude-api add${NC}       - Add new API profile"
cecho "  ${GREEN}claude-api rm${NC}        - Remove API profile"
cecho "  ${GREEN}claude-ac add${NC}        - Add new account"
cecho "  ${GREEN}claude-ac list${NC}       - List all accounts"
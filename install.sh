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

# Create Resources directory (for app icon)
mkdir -p "$INSTALL_DIR/Contents/Resources"

# Copy app icon if it exists
if [ -f "$SCRIPT_DIR/app_icon.png" ]; then
    cp "$SCRIPT_DIR/app_icon.png" "$INSTALL_DIR/Contents/Resources/app_icon.png"
    cecho "${GREEN}✅ App icon copied${NC}"
else
    cecho "${YELLOW}[!] No app_icon.png found, skipping icon installation${NC}"
fi

# Create .icns icon file if possible
if command -v iconutil >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/app_icon.png" ]; then
    mkdir -p "$SCRIPT_DIR/AppIcon.iconset"
    sips -z 16 16 "$SCRIPT_DIR/app_icon.png" --out "$SCRIPT_DIR/AppIcon.iconset/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32 "$SCRIPT_DIR/app_icon.png" --out "$SCRIPT_DIR/AppIcon.iconset/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32 "$SCRIPT_DIR/app_icon.png" --out "$SCRIPT_DIR/AppIcon.iconset/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64 "$SCRIPT_DIR/app_icon.png" --out "$SCRIPT_DIR/AppIcon.iconset/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128 "$SCRIPT_DIR/app_icon.png" --out "$SCRIPT_DIR/AppIcon.iconset/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256 "$SCRIPT_DIR/app_icon.png" --out "$SCRIPT_DIR/AppIcon.iconset/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256 "$SCRIPT_DIR/app_icon.png" --out "$SCRIPT_DIR/AppIcon.iconset/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512 "$SCRIPT_DIR/app_icon.png" --out "$SCRIPT_DIR/AppIcon.iconset/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512 "$SCRIPT_DIR/app_icon.png" --out "$SCRIPT_DIR/AppIcon.iconset/icon_512x512.png" >/dev/null 2>&1
    sips -z 1024 1024 "$SCRIPT_DIR/app_icon.png" --out "$SCRIPT_DIR/AppIcon.iconset/icon_512x512@2x.png" >/dev/null 2>&1

    if iconutil -c icns "$SCRIPT_DIR/AppIcon.iconset" -o "$SCRIPT_DIR/AppIcon.icns" 2>/dev/null; then
        cp "$SCRIPT_DIR/AppIcon.icns" "$INSTALL_DIR/Contents/Resources/"
        cecho "${GREEN}✅ .icns icon created and installed${NC}"
    fi
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
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

# Check required Python files
for pyfile in api_manager.py account_manager.py hook.py notification_hook.py stop_hook.py; do
    if [ ! -f "$SCRIPT_DIR/python/$pyfile" ]; then
        cecho "${RED}❌ Error: $pyfile not found in $SCRIPT_DIR/python/${NC}"
        exit 1
    fi
done

# Copy all Python scripts
cp "$SCRIPT_DIR/python/hook.py" "$BASE_DIR/hook.py"
cp "$SCRIPT_DIR/python/notification_hook.py" "$BASE_DIR/notification_hook.py"
cp "$SCRIPT_DIR/python/stop_hook.py" "$BASE_DIR/stop_hook.py"
cp "$SCRIPT_DIR/python/api_manager.py" "$API_MANAGER_SCRIPT"
cp "$SCRIPT_DIR/python/account_manager.py" "$ACCOUNT_MANAGER_SCRIPT"

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
    local account_alias="\$1"
    local config_path="\$2"
    shift 2

    # 1. Detect Window IMMEDIATELY (before any processing)
    local detected_info=\$("\$_CLAUDE_MON_APP" detect 2>/dev/null)
    local detected_bundle=\$(echo "\$detected_info" | cut -d'|' -f1)
    local detected_pid=\$(echo "\$detected_info" | cut -d'|' -f2)
    local detected_window_id=\$(echo "\$detected_info" | cut -d'|' -f3)

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
cecho "${YELLOW}[4/7] Setting up Claude accounts...${NC}"

# Use space-separated lists (sh compatible)
account_aliases=""
account_paths=""

# Auto-detect existing accounts from config.sh
if [ -f "$CONFIG_FILE" ]; then
    cecho "${YELLOW}[!] Detected existing configuration${NC}"
    while IFS= read -r line; do
        case "$line" in
            alias\ *=\'_claude_wrapper*)
                alias_name=$(echo "$line" | sed 's/alias[[:space:]]*\([^=]*\)=.*/\1/' | tr -d ' ')
                config_path=$(echo "$line" | sed "s/.*_claude_wrapper \"\([^\"]*\)\" \"\([^\"]*\)\".*/\2/")
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
if echo " $account_aliases " | grep -q " c "; then
    has_default=1
    cecho "DEFAULT account ${GREEN}'c'${NC} already configured"
    printf "Keep it? [Y/n]: "
    read keep_default
    keep_default=${keep_default:-Y}
    if [ "$keep_default" = "n" ] || [ "$keep_default" = "N" ]; then
        account_aliases=$(echo "$account_aliases" | sed 's/ c//' | sed 's/^c //' | sed 's/^c$//')
        has_default=0
    fi
fi

if [ $has_default -eq 0 ]; then
    printf "Enter alias for DEFAULT account (default 'c'): "
    read def_alias
    def_alias=${def_alias:-c}
    if ! echo " $account_aliases " | grep -q " $def_alias "; then
        account_aliases="${account_aliases:+$account_aliases }$def_alias"
        account_paths="${account_paths}|$HOME/.claude"
    fi
else
    def_alias="c"
fi

# Additional accounts loop
while true; do
    printf "Add another account? (y/N): "
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
                if echo " $account_aliases " | grep -q " $a_alias "; then
                    cecho "${YELLOW}⚠️  Alias '$a_alias' already exists${NC}"
                    printf "Overwrite? (y/n): "
                    read overwrite
                    if [ "$overwrite" = "y" ] || [ "$overwrite" = "Y" ]; then
                        account_aliases=$(echo "$account_aliases" | sed "s/ $a_alias//" | sed "s/^$a_alias //" | sed "s/^$a_alias$//")
                        break
                    fi
                else
                    break
                fi
            done

            # Input config path with smart default
            smart_default_path="$HOME/.claude-$a_alias"
            while true; do
                printf "Config Path [Default: ${GREEN}$smart_default_path${NC}]: "
                read a_path
                if [ -z "$a_path" ]; then
                    a_path_expanded="$smart_default_path"
                else
                    case "$a_path" in
                        \~/*) a_path_expanded="$HOME${a_path#\~}" ;;
                        *) a_path_expanded="$a_path" ;;
                    esac
                fi
                if [ ! -d "$a_path_expanded" ]; then
                    cecho "${YELLOW}⚠️  Path does not exist: $a_path_expanded${NC}"
                    printf "Create it? (Y/n): "
                    read create_dir
                    create_dir=${create_dir:-Y}
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
            cecho "${GREEN}✅ Added: $a_alias -> $a_path_expanded${NC}"
            ;;
        * ) break;;
    esac
done

# Use Python to generate accounts.json and append aliases to config.sh
cecho "\n${YELLOW}Writing account configuration...${NC}"

ACCOUNT_ALIASES="$account_aliases" \
ACCOUNT_PATHS="$account_paths" \
CONFIG_FILE="$CONFIG_FILE" \
ACCOUNTS_JSON="$BASE_DIR/accounts.json" \
python3 << 'PYEOF'
import os
import json

aliases = os.environ.get('ACCOUNT_ALIASES', '').split()
paths = os.environ.get('ACCOUNT_PATHS', '').split('|')[1:]  # Skip first empty element
config_file = os.environ['CONFIG_FILE']
accounts_json = os.environ['ACCOUNTS_JSON']

if len(aliases) != len(paths):
    print(f"❌ Mismatch: {len(aliases)} aliases vs {len(paths)} paths")
    exit(1)

# Build accounts dict
accounts = {}
for alias, path in zip(aliases, paths):
    if alias and path:
        accounts[alias] = path

# Write accounts.json
with open(accounts_json, 'w') as f:
    json.dump(accounts, f, indent=2)
print(f"✅ Generated {accounts_json}")

# Append aliases to config.sh
with open(config_file, 'a') as f:
    f.write("\n# --- User Aliases ---\n")
    for alias, path in accounts.items():
        f.write(f'alias {alias}=\'_claude_wrapper "{alias}" "{path}"\'\n')
        print(f"   Registered: {alias}")

exit(0)
PYEOF

if [ $? -ne 0 ]; then
    cecho "${RED}❌ Failed to generate account configuration${NC}"
    exit 1
fi

# Store first alias for usage example
first_alias=$(echo "$account_aliases" | awk '{print $1}')
first_alias=${first_alias:-c}

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
cecho "This will enable real-time notifications (idle alerts, permission prompts, etc.)"
echo ""

# Iterate over accounts using the same method as install_monitor.sh
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
        cecho "${YELLOW}[!] settings.json exists for '$alias_name' ($config_path)${NC}"
    fi

    printf "Configure hooks for '$alias_name' ($config_path)? [Y/n]: "
    read install_hook
    install_hook=${install_hook:-Y}
    if [ "$install_hook" = "Y" ] || [ "$install_hook" = "y" ] || [ -z "$install_hook" ]; then
        generate_hooks_config "$config_path"
    fi
done

# ================= 7. Finalize =================
cecho "\n${YELLOW}[7/7] Configuring Shell Integration...${NC}"

RC_FILE="$HOME/.zshrc"
[ -f "$HOME/.bashrc" ] && RC_FILE="$HOME/.bashrc"

SOURCE_CMD="source \"$CONFIG_FILE\""

# Clean up any duplicate/malformed entries first
if grep -q "Claude Monitor" "$RC_FILE" 2>/dev/null; then
    cecho "${YELLOW}[!] Cleaning up existing Claude Monitor entries...${NC}"
    grep -v "Claude Monitor" "$RC_FILE" | grep -v "$CONFIG_FILE" > "${RC_FILE}.tmp"
    mv "${RC_FILE}.tmp" "$RC_FILE"
fi

# Add fresh configuration if not present
if ! grep -q "$CONFIG_FILE" "$RC_FILE" 2>/dev/null; then
    echo "" >> "$RC_FILE"
    echo "# Claude Monitor Hooks" >> "$RC_FILE"
    echo "$SOURCE_CMD" >> "$RC_FILE"
fi
cecho "${GREEN}✅ Shell configuration updated${NC}"

[ -z "$first_alias" ] && first_alias="c"

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
cecho "   2. Test: ${GREEN}$first_alias${NC} (or any configured alias)"
cecho "   3. Settings: ${GREEN}$BINARY_PATH gui${NC}"
cecho "   4. Logs: ${BLUE}~/.claude-hooks/${NC}"
echo ""

cecho "${BLUE}📋 Management Commands:${NC}"
cecho "   ${GREEN}claude-api list${NC}      - List all API profiles"
cecho "   ${GREEN}claude-api add${NC}       - Add new API profile"
cecho "   ${GREEN}claude-api rm${NC}        - Remove API profile"
cecho "   ${GREEN}claude-ac add${NC}        - Add new account"
cecho "   ${GREEN}claude-ac list${NC}       - List all accounts"
echo ""

cecho "${YELLOW}⚠️  Automation Permission (for minimized window restore):${NC}"
cecho "   If notification click doesn't restore minimized windows:"
cecho "   ${BLUE}System Preferences > Privacy & Security > Privacy > Automation${NC}"
cecho "   Allow ${GREEN}ClaudeMonitor${NC} to control ${GREEN}System Events${NC}"
echo ""

cecho "${BLUE}💡 Tip: Run this script again to add/modify accounts${NC}"
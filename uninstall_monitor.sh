#!/bin/sh

# Configuration
APP_NAME="ClaudeMonitor"
INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
BASE_DIR="$HOME/.claude-hooks"
RC_FILE="$HOME/.zshrc"
[ -f "$HOME/.bashrc" ] && RC_FILE="$HOME/.bashrc"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper function for colored output
cecho() {
    printf "%b\n" "$1"
}

cecho "${RED}=== Claude Monitor Uninstaller ===${NC}"

# 1. Stop Processes
echo "Stopping related processes..."
pkill -f "$APP_NAME" || true

# 2. Remove Files
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "Removed App: $INSTALL_DIR"
fi

if [ -d "$BASE_DIR" ]; then
    rm -rf "$BASE_DIR"
    echo "Removed Config: $BASE_DIR"
fi

# 3. Remove hooks configuration from settings.json (NEW) and legacy hooks.json
echo "Searching for hooks configurations in Claude directories..."
REMOVED_HOOKS=0
UPDATED_SETTINGS=0

# Function to remove hooks from settings.json
remove_hooks_from_settings() {
    local settings_file=$1

    if [ ! -f "$settings_file" ]; then
        return 1
    fi

    # Check if settings.json contains our notification_hook.py reference
    if grep -q "notification_hook.py" "$settings_file" 2>/dev/null; then
        cecho "${YELLOW}Found hooks in: $settings_file${NC}"
        echo "This file contains other settings that should be preserved."
        printf "Remove hooks configuration from settings.json? [Y/n]: "
        read remove_hook
        remove_hook=${remove_hook:-Y}

        if [ "$remove_hook" = "Y" ] || [ "$remove_hook" = "y" ]; then
            # Use Python to safely remove hooks key from JSON
            SETTINGS_FILE="$settings_file" python3 << 'PYEOF'
import os
import json

settings_file = os.environ['SETTINGS_FILE']

try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)

    if 'hooks' in settings:
        del settings['hooks']

        with open(settings_file, 'w') as f:
            json.dump(settings, f, indent=2)

        print(f"✅ Removed hooks from {settings_file}")
        exit(0)
    else:
        print(f"No hooks found in {settings_file}")
        exit(1)
except Exception as e:
    print(f"❌ Error processing {settings_file}: {e}")
    print(f"Please manually remove the 'hooks' key from this file.")
    exit(2)
PYEOF
            if [ $? -eq 0 ]; then
                return 0
            fi
        else
            echo "Skipped: $settings_file"
        fi
    fi
    return 1
}

# Process default location
if remove_hooks_from_settings "$HOME/.claude/settings.json"; then
    UPDATED_SETTINGS=$((UPDATED_SETTINGS + 1))
fi

# Also check for legacy hooks.json files
if [ -f "$HOME/.claude/hooks.json" ]; then
    if grep -q "notification_hook.py" "$HOME/.claude/hooks.json" 2>/dev/null; then
        cecho "${YELLOW}Found legacy hooks.json: ~/.claude/hooks.json${NC}"
        printf "Remove legacy hooks.json? [Y/n]: "
        read remove_hook
        remove_hook=${remove_hook:-Y}
        if [ "$remove_hook" = "Y" ] || [ "$remove_hook" = "y" ]; then
            rm -f "$HOME/.claude/hooks.json"
            echo "Removed: ~/.claude/hooks.json"
            REMOVED_HOOKS=$((REMOVED_HOOKS + 1))
        fi
    fi
fi

# Search for other Claude directories
for claude_dir in "$HOME"/.claude-* "$HOME/.config/claude"*; do
    if [ -d "$claude_dir" ]; then
        # Check settings.json
        if remove_hooks_from_settings "$claude_dir/settings.json"; then
            UPDATED_SETTINGS=$((UPDATED_SETTINGS + 1))
        fi

        # Check legacy hooks.json
        if [ -f "$claude_dir/hooks.json" ]; then
            if grep -q "notification_hook.py" "$claude_dir/hooks.json" 2>/dev/null; then
                cecho "${YELLOW}Found legacy hooks.json in: $claude_dir${NC}"
                printf "Remove $claude_dir/hooks.json? [Y/n]: "
                read remove_hook
                remove_hook=${remove_hook:-Y}
                if [ "$remove_hook" = "Y" ] || [ "$remove_hook" = "y" ]; then
                    rm -f "$claude_dir/hooks.json"
                    echo "Removed: $claude_dir/hooks.json"
                    REMOVED_HOOKS=$((REMOVED_HOOKS + 1))
                else
                    echo "Skipped: $claude_dir/hooks.json"
                fi
            fi
        fi
    fi
done

if [ $UPDATED_SETTINGS -eq 0 ] && [ $REMOVED_HOOKS -eq 0 ]; then
    echo "No hooks configurations found."
else
    if [ $UPDATED_SETTINGS -gt 0 ]; then
        cecho "${GREEN}Updated $UPDATED_SETTINGS settings.json file(s)${NC}"
    fi
    if [ $REMOVED_HOOKS -gt 0 ]; then
        cecho "${GREEN}Removed $REMOVED_HOOKS legacy hooks.json file(s)${NC}"
    fi
fi

# 4. Clean Shell Config
CONFIG_PATH_KEY=".claude-hooks/config.sh"

if grep -q "$CONFIG_PATH_KEY" "$RC_FILE"; then
    echo "Cleaning reference from $RC_FILE..."
    
    # Backup
    cp "$RC_FILE" "${RC_FILE}.bak_claude_uninstall"
    
    # Remove lines containing the config path and "Claude Monitor" comments
    grep -v "$CONFIG_PATH_KEY" "${RC_FILE}.bak_claude_uninstall" | grep -v "Claude Monitor" > "$RC_FILE"

    cecho "${GREEN}Cleaned shell config (Backup saved to ${RC_FILE}.bak_claude_uninstall)${NC}"
else
    echo "No reference found in shell config."
fi

cecho "\n${GREEN}=== Uninstallation Complete ===${NC}"
echo "Removed:"
echo "  • ClaudeMonitor.app"
echo "  • ~/.claude-hooks/ (hook.py, notification_hook.py, stream_wrapper.py, config.sh)"
echo "  • Hooks configuration from settings.json files"
echo "  • Legacy hooks.json files (if any)"
echo "  • Shell configuration entries"
cecho "\n${YELLOW}Note:${NC} settings.json files were preserved with other settings intact."
cecho "Please run ${YELLOW}source $RC_FILE${NC} to refresh your terminal session."

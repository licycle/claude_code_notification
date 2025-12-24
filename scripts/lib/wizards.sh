#!/bin/sh
# wizards.sh - Interactive setup wizards for Claude Monitor
# This file is sourced by install.sh

# ================= API Profile Wizard =================

# Run API profile setup wizard
# Requires: API_MANAGER_SCRIPT, GREEN, BLUE, YELLOW, RED, NC, cecho() from common.sh
run_api_wizard() {
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

        local env_vars=""

        # === Standard Environment Variables ===
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
}

# ================= AI Summary Wizard =================

# Run AI summary setup wizard
# Arguments: $1 = TRACKER_CONFIG path
# Requires: GREEN, BLUE, YELLOW, NC, cecho() from common.sh
run_summary_wizard() {
    local tracker_config="$1"

    cecho "\n${BLUE}--- AI Summary Setup ---${NC}"
    cecho "AI Summary uses a third-party API to generate intelligent task summaries."
    cecho "If disabled, notifications will show raw user prompts directly."
    echo ""

    printf "Enable AI Summary? (requires API key) [y/N]: "
    read enable_summary
    enable_summary=${enable_summary:-N}

    if [ "$enable_summary" = "Y" ] || [ "$enable_summary" = "y" ]; then
        printf "  API Base URL (e.g. https://api.openai.com/v1): "
        read summary_base_url
        printf "  API Key: "
        read summary_api_key
        printf "  Model (default: gpt-3.5-turbo): "
        read summary_model
        summary_model=${summary_model:-gpt-3.5-turbo}

        if [ -n "$summary_api_key" ]; then
            python3 << PYEOF
import json
config = {
    "summary": {
        "provider": "third_party",
        "third_party": {
            "enabled": True,
            "base_url": "$summary_base_url",
            "api_key": "$summary_api_key",
            "model": "$summary_model",
            "max_tokens": 500
        }
    },
    "notification": {"enabled": True, "show_progress": True}
}
with open("$tracker_config", "w") as f:
    json.dump(config, f, indent=2)
print("✅ AI Summary enabled")
PYEOF
        else
            cecho "${YELLOW}⚠️ No API key provided, using raw display mode${NC}"
        fi
    else
        python3 << PYEOF
import json
config = {
    "summary": {
        "provider": "disabled",
        "disabled": True
    },
    "notification": {"enabled": True, "show_progress": True}
}
with open("$tracker_config", "w") as f:
    json.dump(config, f, indent=2)
print("✅ AI Summary disabled (raw display mode)")
PYEOF
    fi
}

# ================= Hooks Configuration =================

# Configure hooks for all accounts
# Arguments: $1 = account_aliases, $2 = account_paths
# Requires: generate_hooks_config() from hooks_config.sh
configure_hooks_for_accounts() {
    local aliases="$1"
    local paths="$2"

    local idx=0
    for alias_name in $aliases; do
        [ -z "$alias_name" ] && continue
        idx=$((idx + 1))

        # Extract the idx-th path
        local path_idx=0
        local config_path=""
        IFS='|'
        for path in $paths; do
            path_idx=$((path_idx + 1))
            if [ $path_idx -eq $((idx + 1)) ]; then
                config_path="$path"
                break
            fi
        done
        IFS=' '

        [ -z "$config_path" ] && continue

        # Check if settings.json exists
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
}

# ================= Installation Summary =================

# Print installation summary
# Arguments: $1 = account_aliases, $2 = account_paths, $3 = first_alias, $4 = RC_FILE, $5 = BINARY_PATH
print_installation_summary() {
    local aliases="$1"
    local paths="$2"
    local first_alias="$3"
    local rc_file="$4"
    local binary_path="$5"

    cecho "\n${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    cecho "${GREEN}║     Installation Complete!                    ║${NC}"
    cecho "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
    echo ""

    cecho "${BLUE}Architecture:${NC} ${GREEN}Task Tracker (Unified)${NC}"
    cecho "   Features: Progress tracking, Goal tracking, Rich notifications, Session snapshots"
    echo ""

    cecho "${BLUE}Configured Accounts:${NC}"
    local idx=0
    for alias_name in $aliases; do
        [ -z "$alias_name" ] && continue
        idx=$((idx + 1))
        local path_idx=0
        IFS='|'
        for path in $paths; do
            path_idx=$((path_idx + 1))
            if [ $path_idx -eq $((idx + 1)) ]; then
                cecho "   ${GREEN}$alias_name${NC} -> $path"
                break
            fi
        done
        IFS=' '
    done
    echo ""

    cecho "${YELLOW}Next Steps:${NC}"
    cecho "   1. Run: ${GREEN}source $rc_file${NC}"
    cecho "   2. Test: ${GREEN}$first_alias${NC} (or any configured alias)"
    cecho "   3. Settings: ${GREEN}$binary_path gui${NC}"
    cecho "   4. Logs: ${BLUE}~/.claude-task-tracker/logs/${NC}"
    cecho "   5. Config: ${BLUE}~/.claude-task-tracker/config.json${NC}"
    echo ""

    cecho "${BLUE}Management Commands:${NC}"
    cecho "   ${GREEN}claude-api list${NC}      - List all API profiles"
    cecho "   ${GREEN}claude-api add${NC}       - Add new API profile"
    cecho "   ${GREEN}claude-api rm${NC}        - Remove API profile"
    cecho "   ${GREEN}claude-ac add${NC}        - Add new account"
    cecho "   ${GREEN}claude-ac list${NC}       - List all accounts"
    echo ""

    cecho "${YELLOW}Automation Permission (for minimized window restore):${NC}"
    cecho "   If notification click doesn't restore minimized windows:"
    cecho "   ${BLUE}System Preferences > Privacy & Security > Privacy > Automation${NC}"
    cecho "   Allow ${GREEN}ClaudeMonitor${NC} to control ${GREEN}System Events${NC}"
    echo ""

    cecho "${BLUE}Tip: Run this script again to add/modify accounts${NC}"
}

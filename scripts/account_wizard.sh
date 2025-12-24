#!/bin/sh
# account_wizard.sh - Interactive wizard to setup Claude directories
# This file is sourced by install.sh

# ================= Account Wizard Functions =================

# Run account setup wizard
# Sets global variables: account_aliases, account_paths
# Requires: CONFIG_FILE, GREEN, BLUE, YELLOW, RED, NC, cecho() from common.sh
run_account_wizard() {
    local existing_aliases=""
    if [ -f "$CONFIG_FILE" ]; then
        existing_aliases=$(grep "^alias " "$CONFIG_FILE" | cut -d'=' -f1 | sed 's/alias //')
    fi

    # Initialize output variables
    account_aliases=""
    account_paths=""

    # ================= 1. Default Account Setup (~/.claude) =================
    cecho "\n${BLUE}--- Default Account Setup ---${NC}"
    local default_path="$HOME/.claude"

    printf "Configure default account (path: ${GREEN}~/.claude${NC})? [Y/n]: "
    read yn
    yn=${yn:-Y}

    if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
        # 1. Ask for Alias Name (Default: c)
        local def_alias
        while true; do
            printf "Enter alias name for this account [Default: ${GREEN}c${NC}]: "
            read def_alias
            def_alias=${def_alias:-c}

            # Check duplicates
            if echo "$existing_aliases" | grep -q "^$def_alias$"; then
                cecho "${YELLOW}⚠️  Alias '$def_alias' already exists. Overwrite? (y/n): ${NC}"
                read overwrite
                if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
                    continue
                fi
            fi
            break
        done

        # 2. Ensure directory exists
        if [ ! -d "$default_path" ]; then
            mkdir -p "$default_path"
            cecho "   Created default directory: $default_path"
        fi

        # 3. Save to global variables
        account_aliases="$def_alias"
        account_paths="|$default_path"
        existing_aliases="$existing_aliases
$def_alias"
        cecho "${GREEN}✅ Added alias '$def_alias' -> ~/.claude${NC}"
    else
        cecho "${YELLOW}Skipping default account setup.${NC}"
    fi

    # ================= 2. Custom Accounts Loop =================
    cecho "\n${BLUE}--- Additional Accounts ---${NC}"

    local a_alias a_path a_path_expanded smart_default_path
    while true; do
        printf "\nAdd another custom account? (y/N): "
        read yn
        yn=${yn:-N}
        case $yn in
            [Nn]* ) break;;
            * ) ;;
        esac

        # --- Input Alias ---
        while true; do
            printf "Alias Name (e.g. work, personal): "
            read a_alias
            if [ -z "$a_alias" ]; then continue; fi

            # Check duplicates
            if echo "$existing_aliases" | grep -q "^$a_alias$"; then
                cecho "${YELLOW}⚠️  Alias '$a_alias' already exists. Skip or Overwrite? (s/o): ${NC}"
                read action
                if [ "$action" != "o" ]; then continue; fi
            fi
            break
        done

        # --- Input Path (With Smart Default) ---
        smart_default_path="$HOME/.claude-$a_alias"

        while true; do
            printf "Config Path [Default: ${GREEN}$smart_default_path${NC}]: "
            read a_path

            # Use smart default if empty
            if [ -z "$a_path" ]; then
                a_path_expanded="$smart_default_path"
            else
                # Expand tilde
                case "$a_path" in
                    \~/*) a_path_expanded="$HOME${a_path#\~}" ;;
                    *) a_path_expanded="$a_path" ;;
                esac
            fi

            # Check/Create Directory
            if [ ! -d "$a_path_expanded" ]; then
                printf "Path '$a_path_expanded' does not exist. Create it? [Y/n]: "
                read create_dir
                create_dir=${create_dir:-Y}
                if [ "$create_dir" = "y" ] || [ "$create_dir" = "Y" ]; then
                    mkdir -p "$a_path_expanded"
                    cecho "${GREEN}✅ Directory created.${NC}"
                    break
                else
                    cecho "${RED}Please enter a valid path.${NC}"
                fi
            else
                break
            fi
        done

        # Save to global variables
        account_aliases="${account_aliases:+$account_aliases }$a_alias"
        account_paths="$account_paths|$a_path_expanded"
        existing_aliases="$existing_aliases
$a_alias"
        cecho "${GREEN}✅ Staged: $a_alias -> $a_path_expanded${NC}"
    done
}
#!/bin/sh
# account_wizard.sh - Interactive wizard to setup Claude directories

CONFIG_FILE="$HOME/.claude-hooks/config.sh"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cecho() { printf "%b\n" "$1"; }

cecho "${BLUE}=== Claude Account Setup Wizard ===${NC}"

existing_aliases=""
if [ -f "$CONFIG_FILE" ]; then
    existing_aliases=$(grep "^alias " "$CONFIG_FILE" | cut -d'=' -f1 | sed 's/alias //')
fi

TEMP_OUTPUT="/tmp/claude_new_accounts.txt"
rm -f "$TEMP_OUTPUT"

# ================= 1. Default Account Setup (~/.claude) =================
cecho "\n${BLUE}--- Default Account Setup ---${NC}"
# Logic: We treat the default path ~/.claude as a special case suggestion
default_path="$HOME/.claude"

printf "Configure default account (path: ${GREEN}~/.claude${NC})? [Y/n]: "
read yn
yn=${yn:-Y} # Default to Yes

if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
    
    # 1. Ask for Alias Name (Default: c)
    while true; do
        printf "Enter alias name for this account [Default: ${GREEN}c${NC}]: "
        read def_alias
        def_alias=${def_alias:-c} # Fallback to 'c' if empty

        # Check duplicates
        if echo "$existing_aliases" | grep -q "^$def_alias$"; then
            cecho "${YELLOW}⚠️  Alias '$def_alias' already exists. Overwrite? (y/n): ${NC}"
            read overwrite
            if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
                continue # Ask again
            fi
        fi
        break
    done

    # 2. Ensure directory exists
    if [ ! -d "$default_path" ]; then
        mkdir -p "$default_path"
        cecho "   Created default directory: $default_path"
    fi
    
    # 3. Save
    echo "$def_alias|$default_path" >> "$TEMP_OUTPUT"
    existing_aliases="$existing_aliases
$def_alias"
    cecho "${GREEN}✅ Added alias '$def_alias' -> ~/.claude${NC}"

else
    cecho "${YELLOW}Skipping default account setup.${NC}"
fi

# ================= 2. Custom Accounts Loop =================
cecho "\n${BLUE}--- Additional Accounts ---${NC}"

while true; do
    printf "\nAdd another custom account? (y/N): "
    read yn
    yn=${yn:-N} # Default to No
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

    # Save
    echo "$a_alias|$a_path_expanded" >> "$TEMP_OUTPUT"
    existing_aliases="$existing_aliases
$a_alias"
    cecho "${GREEN}✅ Staged: $a_alias -> $a_path_expanded${NC}"
done
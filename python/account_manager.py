#!/usr/bin/env python3
import os
import json
import sys
import argparse

CONFIG_FILE = os.path.expanduser("~/.claude-hooks/accounts.json")
SHELL_CONFIG = os.path.expanduser("~/.claude-hooks/config.sh")

def load_config():
    if not os.path.exists(CONFIG_FILE):
        return {}
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except:
        return {}

def save_config(config):
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

def update_shell_config(accounts):
    """Update config.sh with new aliases"""
    if not os.path.exists(SHELL_CONFIG):
        print(f"⚠️  Shell config not found: {SHELL_CONFIG}")
        print("   Please run install.sh first.")
        return False

    with open(SHELL_CONFIG, 'r') as f:
        lines = f.readlines()

    # Find the "# --- User Aliases ---" section or end of file
    new_lines = []
    in_alias_section = False
    alias_section_found = False

    for line in lines:
        if '# --- User Aliases ---' in line:
            in_alias_section = True
            alias_section_found = True
            new_lines.append(line)
            # Add all account aliases
            for alias, path in accounts.items():
                new_lines.append(f"alias {alias}='_claude_wrapper \"{path}\"'\n")
            continue

        if in_alias_section:
            # Skip old alias lines
            if line.startswith('alias ') and '_claude_wrapper' in line:
                continue
            else:
                in_alias_section = False

        new_lines.append(line)

    # If no alias section found, append at end
    if not alias_section_found:
        new_lines.append("\n# --- User Aliases ---\n")
        for alias, path in accounts.items():
            new_lines.append(f"alias {alias}='_claude_wrapper \"{path}\"'\n")

    with open(SHELL_CONFIG, 'w') as f:
        f.writelines(new_lines)

    return True

def add_account(alias, path, configure_hooks=False):
    config = load_config()

    # Expand path
    if path.startswith('~'):
        path = os.path.expanduser(path)

    # Create directory if not exists
    if not os.path.exists(path):
        os.makedirs(path, exist_ok=True)
        print(f"📁 Created directory: {path}")

    config[alias] = path
    save_config(config)

    # Update shell config
    if update_shell_config(config):
        print(f"✅ Account '{alias}' added -> {path}")
        print(f"   Run: source ~/.zshrc")

        if configure_hooks:
            configure_hooks_for_account(path)
    else:
        print(f"⚠️  Account saved but shell config not updated")

def remove_account(alias):
    config = load_config()
    if alias in config:
        del config[alias]
        save_config(config)
        if update_shell_config(config):
            print(f"✅ Account '{alias}' removed")
            print(f"   Run: source ~/.zshrc")
        else:
            print(f"⚠️  Account removed but shell config not updated")
    else:
        print(f"⚠️  Account '{alias}' not found")

def list_accounts():
    config = load_config()
    if not config:
        print("No accounts configured.")
        print("Use: claude-ac add <alias> <path>")
        return

    print("Configured Accounts:")
    for alias, path in config.items():
        exists = "✓" if os.path.exists(path) else "✗"
        print(f"  🔹 {alias} -> {path} [{exists}]")

def configure_hooks_for_account(config_path):
    """Configure hooks for an account"""
    hook_script = os.path.expanduser("~/.claude-hooks/notification_hook.py")
    stop_hook = os.path.expanduser("~/.claude-hooks/stop_hook.py")
    settings_file = os.path.join(config_path, "settings.json")

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
        if os.path.exists(settings_file):
            with open(settings_file, 'r') as f:
                settings = json.load(f)
        else:
            settings = {"$schema": "https://json.schemastore.org/claude-code-settings.json"}

        settings['hooks'] = hooks_config

        with open(settings_file, 'w') as f:
            json.dump(settings, f, indent=2)

        print(f"✅ Hooks configured in {settings_file}")
    except Exception as e:
        print(f"❌ Error configuring hooks: {e}")

def main():
    parser = argparse.ArgumentParser(description="Claude Account Manager")
    subparsers = parser.add_subparsers(dest='command')

    add_parser = subparsers.add_parser('add', help='Add a new account')
    add_parser.add_argument('alias', help='Account alias (e.g., cw, cp)')
    add_parser.add_argument('path', help='Config directory path (e.g., ~/.claude-work)')
    add_parser.add_argument('--hooks', action='store_true', help='Configure hooks for this account')

    rm_parser = subparsers.add_parser('rm', help='Remove an account')
    rm_parser.add_argument('alias', help='Account alias to remove')

    subparsers.add_parser('list', help='List all accounts')

    hooks_parser = subparsers.add_parser('hooks', help='Configure hooks for an account')
    hooks_parser.add_argument('alias', help='Account alias')

    args = parser.parse_args()

    if args.command == 'add':
        add_account(args.alias, args.path, args.hooks)
    elif args.command == 'rm':
        remove_account(args.alias)
    elif args.command == 'list':
        list_accounts()
    elif args.command == 'hooks':
        config = load_config()
        if args.alias in config:
            configure_hooks_for_account(config[args.alias])
        else:
            print(f"⚠️  Account '{args.alias}' not found")
    else:
        parser.print_help()

if __name__ == "__main__":
    main()

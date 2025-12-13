#!/usr/bin/env python3
import os
import json
import sys
import argparse
import shlex

CONFIG_FILE = os.path.expanduser("~/.claude-hooks/api_profiles.json")

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

def add_api(name, env_vars):
    config = load_config()
    if name not in config:
        config[name] = {}
    
    for item in env_vars:
        if '=' in item:
            key, val = item.split('=', 1)
            config[name][key] = val
        else:
            print(f"⚠️  Skipping invalid format: {item}")
    
    save_config(config)
    print(f"✅ API profile '{name}' updated.")

def remove_api(name):
    config = load_config()
    if name in config:
        del config[name]
        save_config(config)
        print(f"✅ API profile '{name}' removed.")
    else:
        print(f"⚠️  Profile '{name}' not found.")

def list_apis():
    config = load_config()
    if not config:
        print("No API profiles configured.")
        return
    print("Available API Profiles:")
    for name, vars in config.items():
        print(f"  🔹 {name}")
        for k, v in vars.items():
            display_v = v
            if "KEY" in k.upper() and len(v) > 8:
                display_v = v[:4] + "..." + v[-4:]
            print(f"      {k}={display_v}")

def get_env(name):
    config = load_config()
    if name not in config:
        print(f"echo '⚠️  API profile \"{name}\" not found!';", file=sys.stdout)
        return
    
    data = config[name]
    for key, val in data.items():
        if val:
            print(f"export {key}={shlex.quote(val)}")

def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest='command')

    add_parser = subparsers.add_parser('add')
    add_parser.add_argument('name')
    add_parser.add_argument('vars', nargs='+')

    rm_parser = subparsers.add_parser('rm')
    rm_parser.add_argument('name')

    subparsers.add_parser('list')

    get_parser = subparsers.add_parser('get-env')
    get_parser.add_argument('name')

    args = parser.parse_args()

    if args.command == 'add':
        add_api(args.name, args.vars)
    elif args.command == 'rm':
        remove_api(args.name)
    elif args.command == 'list':
        list_apis()
    elif args.command == 'get-env':
        get_env(args.name)

if __name__ == "__main__":
    main()
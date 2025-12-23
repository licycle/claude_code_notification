#!/bin/sh
# hooks_config.sh - Claude hooks configuration generator
# This file is sourced by install.sh

# ================= Hooks Configuration =================

# Generate hooks configuration in settings.json
# Arguments: $1 = config_dir (Claude config directory)
generate_hooks_config() {
    local config_dir=$1
    local settings_file="$config_dir/settings.json"

    mkdir -p "$config_dir"

    SETTINGS_FILE="$settings_file" \
    BASE_DIR="$BASE_DIR" \
    python3 << 'PYEOF'
import os
import json

settings_file = os.environ['SETTINGS_FILE']
base_dir = os.environ['BASE_DIR']

# Task Tracker hooks (unified architecture)
tracker_goal_hook = f"{base_dir}/task_tracker/hooks/goal_tracker.py"
tracker_progress_hook = f"{base_dir}/task_tracker/hooks/progress_tracker.py"
tracker_notification_hook = f"{base_dir}/task_tracker/hooks/notification_tracker.py"
tracker_snapshot_hook = f"{base_dir}/task_tracker/hooks/snapshot_hook.py"

hooks_config = {
    "UserPromptSubmit": [
        {
            "hooks": [{"type": "command", "command": f"python3 {tracker_goal_hook}", "timeout": 5}]
        }
    ],
    "PostToolUse": [
        {
            "matcher": "TodoWrite|AskUserQuestion",
            "hooks": [{"type": "command", "command": f"python3 {tracker_progress_hook}", "timeout": 5}]
        }
    ],
    "Notification": [
        {
            "hooks": [{"type": "command", "command": f"python3 {tracker_notification_hook}", "timeout": 10}]
        }
    ],
    "Stop": [
        {
            "hooks": [
                {"type": "command", "command": f"python3 {tracker_snapshot_hook}", "timeout": 30}
            ]
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

# Install Task Tracker hooks and services
# Arguments: $1 = TRACKER_SRC, $2 = TRACKER_DIR
install_task_tracker() {
    local tracker_src="$1"
    local tracker_dir="$2"

    # Create directories
    mkdir -p "$tracker_dir/hooks"
    mkdir -p "$tracker_dir/services"

    # Copy hook scripts
    cp "$tracker_src/hooks/utils.py" "$tracker_dir/hooks/"
    cp "$tracker_src/hooks/goal_tracker.py" "$tracker_dir/hooks/"
    cp "$tracker_src/hooks/progress_tracker.py" "$tracker_dir/hooks/"
    cp "$tracker_src/hooks/notification_tracker.py" "$tracker_dir/hooks/"
    cp "$tracker_src/hooks/snapshot_hook.py" "$tracker_dir/hooks/"
    cp "$tracker_src/hooks/session_cleanup.py" "$tracker_dir/hooks/"
    cp "$tracker_src/hooks/session_init.py" "$tracker_dir/hooks/"
    cp "$tracker_src/hooks/__init__.py" "$tracker_dir/hooks/" 2>/dev/null || touch "$tracker_dir/hooks/__init__.py"

    # Make hooks executable
    chmod +x "$tracker_dir/hooks/"*.py

    # Copy service modules
    cp "$tracker_src/__init__.py" "$tracker_dir/"
    cp "$tracker_src/services/__init__.py" "$tracker_dir/services/"
    cp "$tracker_src/services/database.py" "$tracker_dir/services/"
    cp "$tracker_src/services/db_timeline.py" "$tracker_dir/services/"
    cp "$tracker_src/services/db_pending.py" "$tracker_dir/services/"
    cp "$tracker_src/services/summary_service.py" "$tracker_dir/services/"
    cp "$tracker_src/services/notification.py" "$tracker_dir/services/"
    cp "$tracker_src/services/notification_formatter.py" "$tracker_dir/services/"

    # Initialize database
    python3 -c "
import sys
sys.path.insert(0, '$tracker_dir')
from services.database import init_database
init_database()
" 2>/dev/null && return 0 || return 1
}

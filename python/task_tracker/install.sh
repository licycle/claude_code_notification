#!/bin/bash
#
# Task Tracker Installation Script
# Installs the task collaboration system for Claude Code
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKER_DIR="$HOME/.claude-task-tracker"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo "🚀 Installing Claude Task Tracker..."
echo ""

# Create directories
echo "📁 Creating directories..."
mkdir -p "$TRACKER_DIR/hooks"
mkdir -p "$TRACKER_DIR/services"
mkdir -p "$TRACKER_DIR/logs"
mkdir -p "$TRACKER_DIR/state"

# Copy hook scripts
echo "📋 Copying hook scripts..."
cp "$SCRIPT_DIR/hooks/utils.py" "$TRACKER_DIR/hooks/"
cp "$SCRIPT_DIR/hooks/goal_tracker.py" "$TRACKER_DIR/hooks/"
cp "$SCRIPT_DIR/hooks/progress_tracker.py" "$TRACKER_DIR/hooks/"
cp "$SCRIPT_DIR/hooks/notification_tracker.py" "$TRACKER_DIR/hooks/"
cp "$SCRIPT_DIR/hooks/snapshot_hook.py" "$TRACKER_DIR/hooks/"

# Make hooks executable
chmod +x "$TRACKER_DIR/hooks"/*.py

# Copy service modules
echo "📦 Copying service modules..."
cp "$SCRIPT_DIR/__init__.py" "$TRACKER_DIR/"
cp "$SCRIPT_DIR/services/__init__.py" "$TRACKER_DIR/services/"
cp "$SCRIPT_DIR/services/database.py" "$TRACKER_DIR/services/"
cp "$SCRIPT_DIR/services/summary_service.py" "$TRACKER_DIR/services/"
cp "$SCRIPT_DIR/services/notification.py" "$TRACKER_DIR/services/"

# Copy config template if config doesn't exist
if [ ! -f "$TRACKER_DIR/config.json" ]; then
    echo "⚙️ Creating default config..."
    cp "$SCRIPT_DIR/config.template.json" "$TRACKER_DIR/config.json"
else
    echo "⚙️ Config already exists, skipping..."
fi

# Copy hooks.json for reference
cp "$SCRIPT_DIR/hooks.json" "$TRACKER_DIR/hooks.json"

# Initialize database
echo "🗄️ Initializing database..."
python3 -c "
import sys
sys.path.insert(0, '$TRACKER_DIR')
from services.database import init_database
init_database()
print('Database initialized.')
"

# Merge hooks into Claude settings
echo ""
echo "📝 Configuring Claude Code hooks..."

if [ -f "$CLAUDE_SETTINGS" ]; then
    # Backup existing settings
    cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.backup.$(date +%Y%m%d%H%M%S)"
    echo "   Backed up existing settings."

    # Check if hooks already configured
    if grep -q "claude-task-tracker" "$CLAUDE_SETTINGS" 2>/dev/null; then
        echo "   ⚠️ Task tracker hooks already configured in settings."
        echo "   You may need to manually update if there are conflicts."
    else
        echo "   Adding hooks to settings..."

        # Use Python to merge JSON
        python3 << 'PYTHON_SCRIPT'
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")
hooks_path = os.path.expanduser("~/.claude-task-tracker/hooks.json")

# Load existing settings
with open(settings_path, 'r') as f:
    settings = json.load(f)

# Load new hooks
with open(hooks_path, 'r') as f:
    new_hooks = json.load(f)

# Merge hooks
if 'hooks' not in settings:
    settings['hooks'] = {}

for hook_type, hook_configs in new_hooks.get('hooks', {}).items():
    if hook_type not in settings['hooks']:
        settings['hooks'][hook_type] = []

    # Add new hooks
    settings['hooks'][hook_type].extend(hook_configs)

# Write back
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print("   Hooks merged successfully.")
PYTHON_SCRIPT
    fi
else
    echo "   Creating new Claude settings..."
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    cp "$TRACKER_DIR/hooks.json" "$CLAUDE_SETTINGS"
    # Wrap in proper format
    python3 << 'PYTHON_SCRIPT'
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")
hooks_path = os.path.expanduser("~/.claude-task-tracker/hooks.json")

with open(hooks_path, 'r') as f:
    hooks = json.load(f)

with open(settings_path, 'w') as f:
    json.dump(hooks, f, indent=2)

print("   Settings created.")
PYTHON_SCRIPT
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "📍 Installed to: $TRACKER_DIR"
echo ""
echo "📋 Next steps:"
echo "   1. Restart Claude Code for hooks to take effect"
echo "   2. Edit $TRACKER_DIR/config.json to configure:"
echo "      - Third-party API (optional, for AI summaries)"
echo "      - Notification preferences"
echo "   3. Ensure ClaudeMonitor.app is installed for notifications"
echo ""
echo "📚 Files installed:"
echo "   - $TRACKER_DIR/hooks/*.py (hook scripts)"
echo "   - $TRACKER_DIR/services/*.py (service modules)"
echo "   - $TRACKER_DIR/config.json (configuration)"
echo "   - $TRACKER_DIR/tasks.db (SQLite database)"
echo ""

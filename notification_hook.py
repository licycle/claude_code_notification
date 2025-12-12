#!/usr/bin/env python3
"""
notification_hook.py - Claude Code Notification Hook
Triggered by Claude Code's Notification events (idle_prompt, permission_prompt, etc.)
"""
import sys
import json
import subprocess
import os
from pathlib import Path

LOG_FILE = os.path.expanduser("~/.claude-hooks/python_debug.log")
BIN_PATH = os.path.expanduser("~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor")

def log(tag, msg):
    try:
        with open(LOG_FILE, "a") as f:
            from datetime import datetime
            ts = datetime.now().strftime("%H:%M:%S")
            f.write(f"[{ts}] [NOTIF-{tag}] {msg}\n")
    except: pass

def get_account_alias():
    """Get account alias from environment variable or infer from config path"""
    # Prefer explicit alias set by wrapper
    alias = os.environ.get('CLAUDE_ACCOUNT_ALIAS')
    if alias:
        return alias

    # Fallback: infer from CLAUDE_CONFIG_DIR
    config_dir = os.environ.get('CLAUDE_CONFIG_DIR', '')
    if config_dir:
        basename = os.path.basename(config_dir)
        if basename == '.claude':
            return 'default'
        elif basename.startswith('.claude-'):
            return basename[8:]  # Remove '.claude-' prefix

    return 'default'

def main():
    log("START", "Hook triggered by Claude")

    # Read JSON payload from stdin
    try:
        payload = json.load(sys.stdin)
        log("PAYLOAD", f"Received: {json.dumps(payload)}")
    except Exception as e:
        log("ERROR", f"Failed to parse JSON: {e}")
        sys.exit(1)

    notification_type = payload.get("notification_type", "unknown")
    message = payload.get("message", "Notification from Claude")

    log("HOOK", f"Type={notification_type}, Msg={message[:50]}")

    # Notification configuration
    config = {
        "idle_prompt": {
            "title": "Claude Waiting",
            "sound": "Glass",
            "message_prefix": "⚠️ "
        },
        "permission_prompt": {
            "title": "Permission Required",
            "sound": "Sosumi",
            "message_prefix": "🔑 "
        },
        "elicitation_dialog": {
            "title": "Input Needed",
            "sound": "Glass",
            "message_prefix": "📝 "
        },
        "auth_success": {
            "title": "Auth Success",
            "sound": "Glass",
            "message_prefix": "✅ "
        }
    }

    settings = config.get(notification_type, {
        "title": "Claude Notification",
        "sound": "Ping",
        "message_prefix": "🔔 "
    })

    # Log unknown notification types for debugging
    if notification_type not in config and notification_type != "unknown":
        log("UNKNOWN_TYPE", f"Unrecognized notification_type: '{notification_type}' - using default handler")

    # Get account alias and add to title
    account_alias = get_account_alias()
    base_title = settings["title"]
    title = f"{base_title} [{account_alias}]"

    sound = settings["sound"]
    body = settings["message_prefix"] + message

    # Get bundle ID, PID and CGWindowID from environment (set by _claude_wrapper)
    bundle_id = os.environ.get('CLAUDE_TERM_BUNDLE_ID', 'com.apple.Terminal')
    pid = os.environ.get('CLAUDE_TERM_PID', '0')
    cg_window_id = os.environ.get('CLAUDE_CG_WINDOW_ID', '0')

    log("ENV", f"Bundle={bundle_id}, PID={pid}, CGWindowID={cg_window_id}, Alias={account_alias}")

    # Send notification via Swift app with PID and CGWindowID for window-level activation
    cmd = [BIN_PATH, "notify", title, body, sound, bundle_id, pid, cg_window_id]
    log("SEND", f"Calling: {' '.join(cmd[:4])}...")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            log("SUCCESS", f"Notification sent: {title}")
            if result.stdout:
                log("STDOUT", result.stdout)
            sys.exit(0)  # Success
        else:
            log("ERROR", f"Notify failed with code {result.returncode}")
            if result.stderr:
                log("STDERR", result.stderr)
            if result.stdout:
                log("STDOUT", result.stdout)
            sys.exit(2)  # Blocking error (shown to user)
    except subprocess.TimeoutExpired:
        log("FATAL", "Notification command timed out after 10 seconds")
        sys.exit(2)
    except Exception as e:
        log("FATAL", f"Failed to call Swift app: {e}")
        sys.exit(2)  # Blocking error (shown to user)

if __name__ == "__main__":
    main()

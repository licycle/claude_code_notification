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
            "title": "⏳ Claude Waiting",
            "sound": "Glass",
            "message_prefix": "⚠️ "
        },
        "permission_prompt": {
            "title": "🔐 Permission Required",
            "sound": "Sosumi",
            "message_prefix": "🔑 "
        },
        "elicitation_dialog": {
            "title": "⌨️ Input Needed",
            "sound": "Glass",
            "message_prefix": "📝 "
        },
        "auth_success": {
            "title": "✅ Authentication Success",
            "sound": "Glass",
            "message_prefix": "✅ "
        }
    }

    settings = config.get(notification_type, {
        "title": "🔔 Claude Notification",
        "sound": "Ping",
        "message_prefix": "🔔 "
    })

    # Log unknown notification types for debugging
    if notification_type not in config and notification_type != "unknown":
        log("UNKNOWN_TYPE", f"Unrecognized notification_type: '{notification_type}' - using default handler")

    title = settings["title"]
    sound = settings["sound"]
    body = settings["message_prefix"] + message

    # Detect active terminal bundle ID
    log("DETECT", "Finding active terminal...")
    try:
        detect_result = subprocess.run(
            [BIN_PATH, "detect"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if detect_result.returncode != 0:
            log("DETECT_ERR", f"Detect returned code {detect_result.returncode}: {detect_result.stderr}")
        bundle_id = detect_result.stdout.strip() or "com.apple.Terminal"
        log("DETECT", f"Found bundle: {bundle_id}")
    except Exception as e:
        log("DETECT_ERR", f"{e}")
        bundle_id = "com.apple.Terminal"

    # Send notification via Swift app - CAPTURE OUTPUT FOR DEBUGGING
    cmd = [BIN_PATH, "notify", title, body, sound, bundle_id]
    log("SEND", f"Calling: {' '.join(cmd[:3])}...")

    try:
        # Use subprocess.run instead of Popen to wait for completion and capture errors
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

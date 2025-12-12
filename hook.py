#!/usr/bin/env python3
"""
hook.py - Legacy hook script for manual/wrapper-based integration
Called by _claude_wrapper after Claude finishes
"""
import sys
import os
import subprocess
import datetime

LOG_FILE = os.path.expanduser("~/.claude-hooks/python_debug.log")
BIN_PATH = os.path.expanduser("~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor")

def log(tag, msg):
    try:
        with open(LOG_FILE, "a") as f:
            ts = datetime.datetime.now().strftime("%H:%M:%S")
            f.write(f"[{ts}] [{tag}] {msg}\n")
    except: pass

def get_account_alias():
    """Get account alias from environment variable or infer from config path"""
    alias = os.environ.get('CLAUDE_ACCOUNT_ALIAS')
    if alias:
        return alias

    config_dir = os.environ.get('CLAUDE_CONFIG_DIR', '')
    if config_dir:
        basename = os.path.basename(config_dir)
        if basename == '.claude':
            return 'default'
        elif basename.startswith('.claude-'):
            return basename[8:]

    return 'default'

def main():
    # 1. Retrieve Terminal Bundle ID, PID and Window ID from Environment
    bundle_id = os.environ.get('CLAUDE_TERM_BUNDLE_ID', 'com.apple.Terminal')
    pid = os.environ.get('CLAUDE_TERM_PID', '0')
    window_id = os.environ.get('CLAUDE_WINDOW_ID', '')
    alias = get_account_alias()

    # 2. Parse Arguments from Claude Hook
    if len(sys.argv) < 2: return
    status = sys.argv[1]
    details = sys.argv[2] if len(sys.argv) > 2 else "Done"

    log("HOOK", f"Status: {status} | Target: {bundle_id} | PID: {pid} | WindowId: {window_id} | Alias: {alias}")

    # 3. Construct Notification with alias in title
    title = f"Claude Finished [{alias}]"
    sound = "Hero"

    if status == "error":
        title = f"Claude Failed [{alias}]"
        sound = "Basso"
        details = "❌ " + details
    elif status == "input":
        title = f"Input Required [{alias}]"
        sound = "Glass"
        details = "⚠️ " + details
    else:
        details = "✅ " + details

    # 4. Call Swift App (Notifier Mode) with PID and Window ID for window-level activation
    cmd = [BIN_PATH, "notify", title, details, sound, bundle_id, pid, window_id]

    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        log("FATAL", f"Failed to call swift app: {e}")

if __name__ == "__main__":
    main()

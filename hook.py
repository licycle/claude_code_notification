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

def main():
    # 1. Retrieve the Terminal Bundle ID from Environment
    bundle_id = os.environ.get('CLAUDE_TERM_BUNDLE_ID', 'com.apple.Terminal')

    # 2. Parse Arguments from Claude Hook
    if len(sys.argv) < 2: return
    status = sys.argv[1]
    details = sys.argv[2] if len(sys.argv) > 2 else "Done"

    log("HOOK", f"Status: {status} | Target: {bundle_id}")

    # 3. Construct Notification
    title = "Claude Finished"
    sound = "Hero"

    if status == "error":
        title = "Claude Failed"
        sound = "Basso"
        details = "❌ " + details
    elif status == "input":
        title = "Input Required"
        sound = "Glass"
        details = "⚠️ " + details
    else:
        details = "✅ " + details

    # 4. Call Swift App (Notifier Mode)
    cmd = [BIN_PATH, "notify", title, details, sound, bundle_id]

    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        log("FATAL", f"Failed to call swift app: {e}")

if __name__ == "__main__":
    main()

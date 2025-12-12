#!/usr/bin/env python3
"""
stop_hook.py - Claude Code Stop Hook
Triggered by Claude Code's Stop event when the agent finishes
Detects rate limit errors in the transcript
"""
import json
import sys
import subprocess
import os
from collections import deque

LOG_FILE = os.path.expanduser("~/.claude-hooks/python_debug.log")
BIN_PATH = os.path.expanduser("~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor")

RATE_LIMIT_KEYWORDS = [
    'rate limit', 'rate_limit', 'too many requests',
    '429', 'quota exceeded', 'overloaded'
]

def log(tag, msg):
    try:
        from datetime import datetime
        with open(LOG_FILE, "a") as f:
            f.write(f"[{datetime.now():%H:%M:%S}] [STOP-{tag}] {msg}\n")
    except: pass

def get_last_n_lines(filepath, n=3):
    """Read last n lines from file efficiently"""
    try:
        with open(os.path.expanduser(filepath), 'rb') as f:
            return deque(f, n)
    except Exception as e:
        log("ERROR", f"Failed to read file: {e}")
        return []

def detect_rate_limit(transcript_path):
    """Check last 3 records in transcript for rate limit errors"""
    last_lines = get_last_n_lines(transcript_path, 3)

    for line in last_lines:
        try:
            content = line.decode('utf-8', errors='ignore').lower()
            for keyword in RATE_LIMIT_KEYWORDS:
                if keyword in content:
                    return True, keyword
        except: pass

    return False, None

def send_notification(title, body, sound, bundle_id):
    """Call Swift app to send notification"""
    try:
        subprocess.run([BIN_PATH, "notify", title, body, sound, bundle_id], timeout=10)
    except Exception as e:
        log("ERROR", f"Notification failed: {e}")

def main():
    try:
        input_data = json.load(sys.stdin)
    except:
        sys.exit(0)

    transcript_path = input_data.get("transcript_path", "")
    if not transcript_path:
        sys.exit(0)

    log("CHECK", f"Checking last 3 records in {transcript_path}")
    has_rate_limit, keyword = detect_rate_limit(transcript_path)

    if has_rate_limit:
        log("DETECTED", f"Rate limit found: {keyword}")
        bundle_id = os.environ.get('CLAUDE_TERM_BUNDLE_ID', 'com.apple.Terminal')
        send_notification(
            "⚠️ Rate Limit Reached",
            f"Claude API rate limit detected ({keyword})",
            "Basso",
            bundle_id
        )

    sys.exit(0)

if __name__ == "__main__":
    main()

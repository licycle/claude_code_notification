#!/usr/bin/env python3
"""
session_init.py - Session Initialization Script
Called by shell wrapper BEFORE Claude starts to create a pending 'idle' session.
This allows the status bar to show the session immediately when user enters Claude.
"""
import sys
import os
from pathlib import Path

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import log, get_env_info
from services.database import create_pending_session, cleanup_active_sessions_by_shell_pid


def main():
    """Create a pending session for the current project"""
    log("SESSION_INIT", "Script triggered")

    # Get environment info from wrapper
    env_info = get_env_info()
    pending_id = os.environ.get('CLAUDE_PENDING_SESSION_ID', '')
    cwd = os.environ.get('PWD', os.getcwd())

    if not pending_id:
        log("SESSION_INIT", "No CLAUDE_PENDING_SESSION_ID, skipping")
        return

    log("SESSION_INIT", f"Creating pending session: {pending_id[:8]}... for {cwd}")

    # Extract window info
    bundle_id = env_info.get('bundle_id')
    terminal_pid = int(env_info.get('pid', 0)) or None
    shell_pid = int(env_info.get('shell_pid', 0)) or None
    window_id = int(env_info.get('window_id', 0)) or None
    account_alias = env_info.get('account_alias', 'default')

    # Clean up old active sessions for this shell before creating new one
    if shell_pid:
        cleaned = cleanup_active_sessions_by_shell_pid(shell_pid)
        if cleaned > 0:
            log("SESSION_INIT", f"Cleaned up {cleaned} old session(s) for shell_pid={shell_pid}")

    # Create pending session
    create_pending_session(
        pending_id=pending_id,
        project=cwd,
        account_alias=account_alias,
        bundle_id=bundle_id,
        terminal_pid=terminal_pid,
        shell_pid=shell_pid,
        window_id=window_id
    )

    log("SESSION_INIT", f"Pending session created: pending_{pending_id[:8]}...")


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("SESSION_INIT_ERROR", f"Unhandled exception: {e}")

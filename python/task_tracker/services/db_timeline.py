#!/usr/bin/env python3
"""
db_timeline.py - Timeline and Summary Operations
Timeline events, aggregation, session summary, and state file operations
"""
import json
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any

from .database import get_connection, get_session, get_progress, get_pending_decisions


# ============================================================================
# Timeline Operations
# ============================================================================

def add_timeline_event(session_id: str, event_type: str, content: str = None, metadata: Dict = None) -> None:
    """Add an event to the timeline"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        # Get session_pk
        cursor = conn.execute(
            "SELECT id FROM sessions WHERE session_id = ?",
            (session_id,)
        )
        row = cursor.fetchone()
        if not row:
            return
        session_pk = row['id']

        conn.execute(
            """INSERT INTO timeline (session_pk, event_type, content, metadata_json, timestamp)
               VALUES (?, ?, ?, ?, ?)""",
            (session_pk, event_type, content,
             json.dumps(metadata, ensure_ascii=False) if metadata else None, now)
        )


def get_session_timeline(session_id: str, limit: int = 50) -> List[Dict]:
    """Get timeline events for a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT t.* FROM timeline t
               JOIN sessions s ON t.session_pk = s.id
               WHERE s.session_id = ?
               ORDER BY t.timestamp DESC LIMIT ?""",
            (session_id, limit)
        )
        results = []
        for row in cursor.fetchall():
            item = dict(row)
            if item.get('metadata_json'):
                item['metadata'] = json.loads(item['metadata_json'])
            results.append(item)
        return results


# ============================================================================
# Timeline Node Aggregation (v2 UI Support)
# ============================================================================

def aggregate_timeline_nodes(session_id: str, max_nodes: int = 20) -> List[Dict]:
    """
    Aggregate raw timeline events into meaningful nodes for UI display.
    """
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT t.* FROM timeline t
               JOIN sessions s ON t.session_pk = s.id
               WHERE s.session_id = ?
               ORDER BY t.timestamp ASC""",
            (session_id,)
        )
        raw_events = [dict(row) for row in cursor.fetchall()]

    if not raw_events:
        return []

    nodes = []
    last_event_time = None
    consecutive_progress = 0
    last_completed_count = 0
    last_status = None

    for event in raw_events:
        try:
            event_time = datetime.fromisoformat(event['timestamp'])
        except (ValueError, TypeError):
            continue

        event_type = event.get('event_type', '')
        content = event.get('content', '') or ''
        metadata = {}
        if event.get('metadata_json'):
            try:
                metadata = json.loads(event['metadata_json'])
            except (json.JSONDecodeError, TypeError):
                pass

        # Skip if too close to last event (< 30 seconds) for status_change
        if last_event_time and event_type == 'status_change':
            time_diff = (event_time - last_event_time).total_seconds()
            if time_diff < 30:
                continue

        node = None

        # Handle different event types
        if event_type == 'goal_set':
            node = {
                'time': event_time.strftime('%H:%M'),
                'type': 'start',
                'title': '开始任务',
                'description': content[:50] if content else '任务开始',
                'status': 'completed'
            }

        elif event_type == 'status_change':
            if content == last_status:
                continue
            last_status = content

            if content == 'waiting_for_user':
                node = {
                    'time': event_time.strftime('%H:%M'),
                    'type': 'waiting',
                    'title': '等待决策',
                    'description': '需要用户输入',
                    'status': 'current'
                }
            elif content == 'waiting_permission':
                node = {
                    'time': event_time.strftime('%H:%M'),
                    'type': 'permission',
                    'title': '等待权限',
                    'description': '需要权限确认',
                    'status': 'current'
                }
            elif content == 'completed':
                node = {
                    'time': event_time.strftime('%H:%M'),
                    'type': 'complete',
                    'title': '任务完成',
                    'description': '已完成全部步骤',
                    'status': 'completed'
                }

        elif event_type == 'progress_update':
            completed = metadata.get('completed', 0)
            total = metadata.get('total', 0)

            if completed > last_completed_count:
                consecutive_progress += (completed - last_completed_count)
            last_completed_count = completed

            if consecutive_progress >= 3:
                node = {
                    'time': event_time.strftime('%H:%M'),
                    'type': 'milestone',
                    'title': '阶段完成',
                    'description': f'已完成 {completed}/{total} 项',
                    'status': 'completed'
                }
                consecutive_progress = 0

            if completed == total and total > 0:
                node = {
                    'time': event_time.strftime('%H:%M'),
                    'type': 'complete',
                    'title': '全部完成',
                    'description': f'已完成全部 {total} 项任务',
                    'status': 'completed'
                }

        if node:
            nodes.append(node)
            last_event_time = event_time

    if nodes and nodes[-1]['type'] not in ['complete']:
        nodes[-1]['status'] = 'current'

    return nodes[-max_nodes:] if len(nodes) > max_nodes else nodes


# ============================================================================
# Session Summary
# ============================================================================

def get_round_count(session_id: str) -> int:
    """
    Get user input round count (goal_set + user_input events)
    """
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT COUNT(*) FROM timeline t
               JOIN sessions s ON t.session_pk = s.id
               WHERE s.session_id = ?
               AND t.event_type IN ('goal_set', 'user_input')""",
            (session_id,)
        )
        return cursor.fetchone()[0]


def get_latest_user_input(session_id: str) -> Optional[str]:
    """
    Get latest user input content
    """
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT t.content FROM timeline t
               JOIN sessions s ON t.session_pk = s.id
               WHERE s.session_id = ?
               AND t.event_type IN ('goal_set', 'user_input')
               ORDER BY t.timestamp DESC
               LIMIT 1""",
            (session_id,)
        )
        row = cursor.fetchone()
        return row[0] if row else None


def get_session_summary(session_id: str) -> Optional[Dict]:
    """
    Get aggregated session summary for menu bar display.
    """
    session = get_session(session_id)
    if not session:
        return None

    progress = get_progress(session_id)
    pending_list = get_pending_decisions(session_id)
    timeline_nodes = aggregate_timeline_nodes(session_id, max_nodes=10)

    return {
        'session_id': session_id,
        'project': session.get('project', ''),
        'original_goal': session.get('original_goal', ''),
        'status': session.get('current_status', 'unknown'),
        'completed': progress.get('completed_count', 0) if progress else 0,
        'total': progress.get('total_count', 0) if progress else 0,
        'todos': progress.get('todos', []) if progress else [],
        'pending_question': pending_list[0].get('question') if pending_list else None,
        'pending_options': json.loads(pending_list[0].get('options_json', '[]')) if pending_list else [],
        'timeline': timeline_nodes,
        'last_activity': session.get('last_activity', ''),
        'created_at': session.get('created_at', ''),
        'account_alias': session.get('account_alias', 'default'),
        'bundle_id': session.get('bundle_id'),
        'terminal_pid': session.get('terminal_pid'),
        'window_id': session.get('window_id'),
        'round_count': get_round_count(session_id)
    }


# ============================================================================
# State File Operations
# ============================================================================

def write_state_file_for_swift():
    """
    Write all session summaries to state file for Swift app to read.
    """
    from .db_pending import get_all_session_summaries

    state_dir = Path.home() / '.claude-task-tracker' / 'state'
    state_dir.mkdir(parents=True, exist_ok=True)

    summaries = get_all_session_summaries()

    all_sessions_file = state_dir / 'all_sessions.json'
    with open(all_sessions_file, 'w') as f:
        json.dump({s['session_id']: s for s in summaries}, f, indent=2, ensure_ascii=False)


__all__ = [
    'add_timeline_event',
    'get_session_timeline',
    'aggregate_timeline_nodes',
    'get_round_count',
    'get_latest_user_input',
    'get_session_summary',
    'write_state_file_for_swift',
]

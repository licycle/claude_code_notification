#!/usr/bin/env python3
"""
notification_formatter.py - Notification Content Formatter

v2 Format (user specified):
- title:    {account} {session_id[:4]} {status} {round}   (账号+session前4位+状态+第几轮)
- subtitle: {current_task_summary}                        (当前任务总结一句话)
- body:     {original_goal/actual_content}                (实际需求和任务内容)
"""
from typing import Dict, Optional

# Status emoji mapping
STATUS_EMOJI = {
    'decision_needed': '\u26a0\ufe0f',   # Warning sign
    'idle': '\U0001f4a4',                 # Zzz
    'permission_needed': '\U0001f510',    # Lock
    'completed': '\u2705',                # Check mark
    'working': '\U0001f504',              # Arrows cycle
    'rate_limited': '\u23f1\ufe0f',       # Stopwatch
    'progress': '\U0001f4c8',             # Chart increasing
}

# Status display text mapping (shorter for title)
STATUS_TEXT = {
    'decision_needed': '决策',
    'idle': '空闲',
    'permission_needed': '权限',
    'completed': '完成',
    'working': '运行',
    'rate_limited': '限流',
    'progress': '进度',
}


def format_title(
    notification_type: str,
    account_alias: str = None,
    session_id: str = None,
    completed: int = 0,
    total: int = 0
) -> str:
    """
    Format notification title
    Format: {account} {session[:4]} {emoji}{status} {completed}/{total}
    Example: personal abc1 空闲 3/5
    """
    parts = []

    # Account alias
    if account_alias and account_alias != 'default':
        parts.append(account_alias[:8])
    else:
        parts.append('default')

    # Session ID (first 4 chars)
    if session_id:
        parts.append(session_id[:4])

    # Status with emoji
    emoji = STATUS_EMOJI.get(notification_type, '')
    status_text = STATUS_TEXT.get(notification_type, '通知')
    parts.append(f"{emoji}{status_text}")

    # Progress (round count)
    if total > 0:
        parts.append(f"{completed}/{total}")

    return ' '.join(parts)


def format_subtitle(
    current_task: str = None,
    project_name: str = None
) -> str:
    """
    Format notification subtitle - current task summary (one sentence)
    """
    if current_task:
        # Truncate to ~40 chars for subtitle
        if len(current_task) > 40:
            return current_task[:37] + '...'
        return current_task

    # Fallback to project name
    if project_name:
        return f"项目: {project_name[:30]}"

    return ""


def format_body(
    original_goal: str = None,
    message: str = None,
    pending_question: str = None
) -> str:
    """
    Format notification body - actual requirements and task content
    Shows: original goal or pending question
    """
    # Pending question takes priority (actionable)
    if pending_question:
        if len(pending_question) > 100:
            return pending_question[:97] + '...'
        return pending_question

    # Original goal (actual requirement)
    if original_goal:
        if len(original_goal) > 100:
            return original_goal[:97] + '...'
        return original_goal

    # Fallback to message
    if message:
        if len(message) > 100:
            return message[:97] + '...'
        return message

    return ""


def format_notification(
    notification_type: str,
    session_id: str = None,
    account_alias: str = None,
    completed: int = 0,
    total: int = 0,
    current_task: str = None,
    project_name: str = None,
    original_goal: str = None,
    message: str = None,
    pending_question: str = None,
    summary: Dict = None,
    **kwargs  # Accept extra args for compatibility
) -> Dict[str, str]:
    """
    Format complete notification with title, subtitle, and body.

    Normal mode (AI summary enabled):
        Title:    {account} {session[:4]} {status} {progress}
        Subtitle: {current_task_summary}
        Body:     {original_goal/pending_question}

    Raw mode (AI summary disabled):
        Title:    {account} {session[:4]} {status} {progress}
        Subtitle: User: {user_prompt_preview}
        Body:     [AI Request: {pending_question}] or {original_goal}

    Returns:
        Dict with 'title', 'subtitle', 'body' keys
    """
    # Check if using raw mode (no AI summary)
    if summary and summary.get('mode') == 'raw':
        return format_raw_notification(
            notification_type=notification_type,
            session_id=session_id,
            account_alias=account_alias,
            completed=completed,
            total=total,
            summary=summary,
            project_name=project_name,
            original_goal=original_goal
        )

    # Normal mode with AI summary
    return {
        'title': format_title(
            notification_type,
            account_alias,
            session_id,
            completed,
            total
        ),
        'subtitle': format_subtitle(current_task, project_name),
        'body': format_body(original_goal, message, pending_question)
    }


def format_raw_notification(
    notification_type: str,
    session_id: str = None,
    account_alias: str = None,
    completed: int = 0,
    total: int = 0,
    summary: Dict = None,
    project_name: str = None,
    original_goal: str = None
) -> Dict[str, str]:
    """
    Format notification in raw mode (no AI summary).

    Shows user's actual prompt and AI's pending question directly.

    Title:    {account} {session[:4]} {status} {progress}
    Subtitle: {user_prompt_preview} (truncated user input)
    Body:     {pending_question} or {current_task}
    """
    summary = summary or {}

    # Title stays the same
    title = format_title(
        notification_type,
        account_alias,
        session_id,
        completed,
        total
    )

    # Subtitle: Show user prompt preview
    user_prompt = summary.get('user_prompt', '')
    if user_prompt:
        # Truncate and clean up for subtitle
        user_prompt = user_prompt.replace('\n', ' ').strip()
        if len(user_prompt) > 50:
            subtitle = user_prompt[:47] + '...'
        else:
            subtitle = user_prompt
    else:
        subtitle = project_name or ''

    # Body: Show pending question (AI needs help) or current task
    pending_q = summary.get('pending_question', '')
    if pending_q:
        body = f"AI需要协助: {pending_q}"
    else:
        current_task = summary.get('current_task', '')
        if current_task:
            body = current_task
        else:
            body = original_goal[:100] if original_goal else ''

    return {
        'title': title,
        'subtitle': subtitle,
        'body': body
    }


# Convenience function for getting category identifier
def get_category_identifier(notification_type: str) -> str:
    """Get notification category identifier for Swift app"""
    category_map = {
        'decision_needed': 'DECISION_NEEDED',
        'permission_needed': 'PERMISSION_NEEDED',
        'idle': 'TASK_STATUS',
        'completed': 'TASK_STATUS',
        'working': 'TASK_STATUS',
        'progress': 'TASK_STATUS',
        'rate_limited': 'TASK_STATUS',
    }
    return category_map.get(notification_type, 'TASK_STATUS')

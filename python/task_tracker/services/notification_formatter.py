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

# Status display text mapping (English)
STATUS_TEXT = {
    'decision_needed': 'Decision Needed',
    'idle': 'Idle',
    'permission_needed': 'Permission',
    'completed': 'Completed',
    'working': 'Working',
    'rate_limited': 'Rate Limited',
    'progress': 'Progress',
}


def format_title(
    notification_type: str,
    account_alias: str = None,
    session_id: str = None,
    round_count: int = 0,
    **kwargs  # Accept extra args for compatibility
) -> str:
    """
    Format notification title
    New format: {emoji} {status} [{account}][{session_id}] R{round}
    Example: ⚠️ Decision Needed [personal][5f95] R7
    """
    # emoji + status text
    emoji = STATUS_EMOJI.get(notification_type, '')
    status_text = STATUS_TEXT.get(notification_type, 'Notification')

    # account tag
    account_part = f"[{account_alias[:8]}]" if account_alias and account_alias != 'default' else ''

    # session_id tag
    session_part = f"[{session_id[:4]}]" if session_id else ''

    # round count
    round_part = f" R{round_count}" if round_count > 0 else ''

    return f"{emoji} {status_text} {account_part}{session_part}{round_part}".strip()


def format_subtitle(
    current_task: str = None,
    project_name: str = None,
    round_count: int = 0,
    mode: str = None,  # 'ai' or 'raw'
    **kwargs  # Accept extra args for compatibility
) -> str:
    """
    Format notification subtitle - mode tag + task summary
    New format: [{mode}] {task_summary}
    Example: [AI] Refactoring auth module
    """
    # mode tag
    mode_tag = f"[{mode.upper()}] " if mode else ''

    # task summary (shorter to accommodate mode tag)
    max_len = 30 if mode else 35
    task_summary = current_task or project_name or ''
    if len(task_summary) > max_len:
        task_summary = task_summary[:max_len - 3] + '...'

    return f"{mode_tag}{task_summary}"


def format_body(
    notification_type: str = None,
    original_goal: str = None,
    message: str = None,
    pending_question: str = None
) -> str:
    """
    Format notification body - actual requirements and task content
    Shows different content based on notification type
    """
    # Task completed
    if notification_type == 'completed':
        return "All steps completed"

    # Permission needed
    if notification_type == 'permission_needed' and message:
        content = message[:70]
        return f"Request: {content}"

    # Pending question takes priority
    if pending_question:
        if len(pending_question) > 80:
            return pending_question[:77] + '...'
        return pending_question

    # Original goal
    if original_goal:
        if len(original_goal) > 80:
            return original_goal[:77] + '...'
        return original_goal

    # Fallback to message
    if message:
        if len(message) > 80:
            return message[:77] + '...'
        return message

    return ""


def format_notification(
    notification_type: str,
    session_id: str = None,
    account_alias: str = None,
    round_count: int = 0,
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

    New format:
        Title:    {emoji} {status} [{account}][{session_id}] R{round}
        Subtitle: {task_summary}
        Body:     {key_info/question/next_step}

    Raw mode (AI summary disabled):
        Title:    {emoji} {status} [{account}][{session_id}] R{round}
        Subtitle: [RAW] {user_prompt_preview}
        Body:     {pending_question} or {current_task}

    Returns:
        Dict with 'title', 'subtitle', 'body' keys
    """
    # Check if using raw mode (no AI summary)
    if summary and summary.get('mode') == 'raw':
        return format_raw_notification(
            notification_type=notification_type,
            session_id=session_id,
            account_alias=account_alias,
            round_count=round_count,
            summary=summary,
            project_name=project_name,
            original_goal=original_goal
        )

    # Determine mode tag: only show [AI] if we actually have AI-generated content
    # If summary exists and has AI-generated content, show [AI]
    # Otherwise, no mode tag (None)
    mode_tag = None
    if summary and summary.get('mode') == 'ai' and summary.get('ai_summary'):
        mode_tag = 'ai'

    # Normal mode
    return {
        'title': format_title(
            notification_type,
            account_alias,
            session_id,
            round_count
        ),
        'subtitle': format_subtitle(current_task, project_name, round_count, mode=mode_tag),
        'body': format_body(notification_type, original_goal, message, pending_question)
    }


def format_raw_notification(
    notification_type: str,
    session_id: str = None,
    account_alias: str = None,
    round_count: int = 0,
    summary: Dict = None,
    project_name: str = None,
    original_goal: str = None
) -> Dict[str, str]:
    """
    Format notification in raw mode (no AI summary).

    Shows user's actual prompt and AI's pending question directly.

    Title:    {emoji} {status} [{account}][{session_id}] R{round}
    Subtitle: [RAW] {user_prompt_preview}
    Body:     {pending_question} or {current_task}
    """
    summary = summary or {}

    # Title with round count
    title = format_title(
        notification_type,
        account_alias,
        session_id,
        round_count
    )

    # Subtitle: Show user prompt preview + RAW mode tag
    user_prompt = summary.get('user_prompt', '')
    if user_prompt:
        # Truncate and clean up for subtitle
        user_prompt = user_prompt.replace('\n', ' ').strip()
        if len(user_prompt) > 25:
            task_summary = user_prompt[:22] + '...'
        else:
            task_summary = user_prompt
    else:
        task_summary = project_name or ''
        if len(task_summary) > 25:
            task_summary = task_summary[:22] + '...'

    subtitle = f"[RAW] {task_summary}"

    # Body: Show pending question (AI needs help) or current task
    pending_q = summary.get('pending_question', '')
    if pending_q:
        body = f"AI needs input: {pending_q[:60]}"
    else:
        current_task = summary.get('current_task', '')
        if current_task:
            body = current_task[:80]
        else:
            body = original_goal[:80] if original_goal else ''

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

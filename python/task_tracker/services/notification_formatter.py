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
    mode: str = None,  # 'ai' or 'raw'
    **kwargs  # Accept extra args for compatibility
) -> str:
    """
    Format notification title
    New format: {emoji} [{mode}] {status} [{account}][{session_id}] R{round}
    Example: ⚠️ [AI] Decision Needed [personal][5f95] R7
    """
    # emoji + status text
    emoji = STATUS_EMOJI.get(notification_type, '')
    status_text = STATUS_TEXT.get(notification_type, 'Notification')

    # mode tag [AI] or [Raw]
    mode_part = f"[{mode.upper()}] " if mode else ''

    # account tag
    account_part = f"[{account_alias[:8]}]" if account_alias and account_alias != 'default' else ''

    # session_id tag
    session_part = f"[{session_id[:4]}]" if session_id else ''

    # round count
    round_part = f" R{round_count}" if round_count > 0 else ''

    return f"{emoji} {mode_part}{status_text} {account_part}{session_part}{round_part}".strip()


def format_subtitle(
    content: str = None,
    max_len: int = 50,
    **kwargs  # Accept extra args for compatibility
) -> str:
    """
    Format notification subtitle - simple content display
    """
    if not content:
        return ''

    content = content.replace('\n', ' ').strip()
    if len(content) > max_len:
        return content[:max_len - 3] + '...'
    return content


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

    AI mode (summary.mode == 'ai'):
        Title:    {emoji} [AI] {status} [{account}][{session_id}] R{round}
        Subtitle: {user_input} (用户输入)
        Body:     {ai_summary} (AI总结内容)

    Raw mode (summary.mode == 'raw'):
        Title:    {emoji} [Raw] {status} [{account}][{session_id}] R{round}
        Subtitle: {original_goal} (first user prompt)
        Body:     {latest_user_input} or {pending_question}

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

    # AI mode - subtitle shows user input, body shows AI summary
    mode_tag = 'ai' if summary and summary.get('mode') == 'ai' else None

    # Get user input for subtitle
    user_input = original_goal or ''
    if summary:
        # Prefer latest user prompt from summary
        user_input = summary.get('user_prompt') or original_goal or ''

    # Get AI summary for body
    if mode_tag == 'ai' and summary:
        # AI mode: body shows AI-generated summary
        ai_summary = summary.get('summary') or summary.get('current_task') or ''
        if pending_question:
            # If there's a pending question, show it
            body = f"AI asks: {pending_question[:70]}"
        elif ai_summary:
            body = ai_summary[:80] if len(ai_summary) <= 80 else ai_summary[:77] + '...'
        else:
            body = format_body(notification_type, original_goal, message, pending_question)
    else:
        # No AI mode, use default body formatting
        body = format_body(notification_type, original_goal, message, pending_question)

    return {
        'title': format_title(
            notification_type,
            account_alias,
            session_id,
            round_count,
            mode=mode_tag
        ),
        'subtitle': format_subtitle(user_input),
        'body': body
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

    Title:    {emoji} [Raw] {status} [{account}][{session_id}] R{round}
    Subtitle: {original_goal} (first user prompt)
    Body:     {latest_user_input} or {pending_question}
    """
    summary = summary or {}

    # Title: Status info with emoji, [Raw] tag, account, session, round
    title = format_title(
        notification_type,
        account_alias,
        session_id,
        round_count,
        mode='raw'  # Add [Raw] tag to title
    )

    # Subtitle: Show first user prompt (original_goal)
    first_prompt = original_goal or ''
    if first_prompt:
        first_prompt = first_prompt.replace('\n', ' ').strip()
        if len(first_prompt) > 50:
            subtitle = first_prompt[:47] + '...'
        else:
            subtitle = first_prompt
    else:
        subtitle = project_name or 'Claude Task'

    # Body: Show latest user input or pending question
    user_prompt = summary.get('user_prompt', '')
    pending_q = summary.get('pending_question', '')

    if pending_q:
        # AI needs user input - show the question
        body = f"AI needs input: {pending_q[:70]}"
    elif user_prompt:
        # Show latest user input
        user_prompt = user_prompt.replace('\n', ' ').strip()
        if len(user_prompt) > 80:
            body = user_prompt[:77] + '...'
        else:
            body = user_prompt
    else:
        body = ''

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

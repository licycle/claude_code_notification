#!/usr/bin/env python3
"""
summary_service.py - Task Summary Service
Supports multiple providers: Third-party API, Claude Session, Extraction Only
"""
import json
import subprocess
import os
import socket
import sys
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Dict, Optional

# Add parent path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
from hooks.utils import log

# Config path
CONFIG_DIR = Path.home() / '.claude-task-tracker'
CONFIG_PATH = CONFIG_DIR / 'config.json'


def _log(tag: str, msg: str):
    """Log to summary.log"""
    log(tag, msg, log_file='summary.log')

# Default summary prompt
SUMMARY_SYSTEM_PROMPT = """你是一个任务状态总结助手。请根据提供的上下文生成简洁的任务状态总结。
输出格式为 JSON：
{
  "current_task": "当前正在进行的具体任务（15字以内）",
  "progress_summary": "进度概述（20字以内）",
  "pending_decision": "待用户决定的问题（如果有，否则为null）",
  "next_step": "建议的下一步（15字以内）"
}
只输出 JSON，不要其他内容。"""


class SummaryProvider(ABC):
    """Abstract base class for summary providers"""

    @abstractmethod
    def generate_summary(self, context: dict) -> dict:
        pass

    def _build_prompt(self, context: dict) -> str:
        """Build prompt from context"""
        todos_str = ""
        if context.get('todos'):
            todos_str = "\n".join([
                f"- [{t.get('status', 'pending')}] {t.get('content', '')}"
                for t in context['todos']
            ])

        return f"""请总结以下任务的当前状态：

原始目标：{context.get('original_goal', '未知')}

最后用户消息：{context.get('last_user_message', '')[:300]}

最后助手回复：{context.get('last_assistant_message', '')[:300]}

当前 TODO 列表：
{todos_str or '无'}

请用 JSON 格式返回总结。"""

    def _parse_response(self, content: str) -> dict:
        """Parse JSON from response"""
        try:
            import re
            # Try to extract JSON from response
            json_match = re.search(r'\{[\s\S]*?\}', content)
            if json_match:
                return json.loads(json_match.group())
        except (json.JSONDecodeError, AttributeError):
            pass
        return {"current_task": "解析失败", "raw_response": content[:200]}

    def _fallback_summary(self, context: dict, error: str = None) -> dict:
        """Generate fallback summary without AI"""
        todos = context.get('todos', [])
        completed = sum(1 for t in todos if t.get('status') == 'completed')
        total = len(todos)

        return {
            "current_task": context.get('original_goal', '')[:50],
            "progress_summary": f"已完成 {completed}/{total} 项" if total > 0 else "进行中",
            "pending_decision": context.get('pending_question'),
            "next_step": None,
            "error": error
        }


class ThirdPartyProvider(SummaryProvider):
    """OpenAI-compatible third-party API provider"""

    def __init__(self, config: dict):
        self.base_url = config.get('base_url', '').rstrip('/')
        self.api_key = config.get('api_key', '')
        self.model = config.get('model', 'gpt-3.5-turbo')
        self.max_tokens = config.get('max_tokens', 500)
        self.timeout = config.get('timeout', 60)  # Default 60 seconds

    def generate_summary(self, context: dict) -> dict:
        try:
            import urllib.request
            import urllib.error
            import ssl

            _log("API", f"Calling {self.base_url} model={self.model}")

            prompt = self._build_prompt(context)

            data = json.dumps({
                "model": self.model,
                "messages": [
                    {"role": "system", "content": SUMMARY_SYSTEM_PROMPT},
                    {"role": "user", "content": prompt}
                ],
                "max_tokens": self.max_tokens,
                "temperature": 0.3
            }).encode('utf-8')

            req = urllib.request.Request(
                f"{self.base_url}/chat/completions",
                data=data,
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json"
                }
            )

            # Create SSL context that doesn't verify certificates (for proxy environments)
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE

            with urllib.request.urlopen(req, timeout=self.timeout, context=ssl_context) as response:
                result = json.loads(response.read().decode('utf-8'))
                _log("API", f"Response: {json.dumps(result, ensure_ascii=False)[:500]}")

                message = result['choices'][0]['message']
                # Only use 'content' (final answer), ignore 'reasoning_content' (thinking process)
                # Thinking models may return empty content if max_tokens is insufficient
                content = message.get('content', '')
                _log("API", f"Content: {content[:200] if content else '(empty)'}")

                if not content:
                    # Empty response (common with thinking models) - fallback to raw
                    _log("API", "Empty content, fallback to raw")
                    return self._fallback_to_raw(context, "Empty API response (try non-thinking model)")

                parsed = self._parse_response(content)
                _log("API", f"Parsed: {json.dumps(parsed, ensure_ascii=False)[:200]}")

                # Check if parse actually succeeded
                if parsed.get('current_task') == '解析失败':
                    _log("API", "Parse failed, fallback to raw")
                    return self._fallback_to_raw(context, f"JSON parse failed: {parsed.get('raw_response', '')[:50]}")
                parsed['mode'] = 'ai'  # Mark as AI mode
                return parsed

        except urllib.error.URLError as e:
            _log("API_ERROR", f"URLError: {e.reason}")
            return self._fallback_to_raw(context, f"API error: {e.reason}")
        except (TimeoutError, socket.timeout):
            _log("API_ERROR", "Timeout")
            return self._fallback_to_raw(context, "API timeout")
        except Exception as e:
            _log("API_ERROR", f"Exception: {e}")
            return self._fallback_to_raw(context, str(e))

    def _fallback_to_raw(self, context: dict, error: str = None) -> dict:
        """Fallback to RAW mode when AI fails"""
        _log("FALLBACK", f"Switching to raw mode: {error}")
        raw_provider = DisabledProvider({})
        result = raw_provider.generate_summary(context)
        result['fallback_reason'] = error
        return result


class ClaudeSessionProvider(SummaryProvider):
    """Use Claude Code session API via claude CLI"""

    def __init__(self, config: dict):
        self.model = config.get('model', 'haiku')
        self.max_tokens = config.get('max_tokens', 500)

    def generate_summary(self, context: dict) -> dict:
        prompt = SUMMARY_SYSTEM_PROMPT + "\n\n" + self._build_prompt(context)

        try:
            result = subprocess.run(
                ['claude', '--model', self.model, '--print', '-p', prompt],
                capture_output=True,
                text=True,
                timeout=60,
                env={**os.environ, 'ANTHROPIC_API_KEY': os.environ.get('ANTHROPIC_API_KEY', '')}
            )

            if result.returncode == 0 and result.stdout.strip():
                return self._parse_response(result.stdout)
            else:
                return self._fallback_summary(context, result.stderr or "Claude 调用失败")

        except subprocess.TimeoutExpired:
            return self._fallback_summary(context, "Claude 调用超时")
        except FileNotFoundError:
            return self._fallback_summary(context, "claude 命令未找到")
        except Exception as e:
            return self._fallback_summary(context, str(e))


class ExtractionOnlyProvider(SummaryProvider):
    """Extract key information without AI"""

    def __init__(self, config: dict):
        self.max_length = config.get('max_preview_length', 200)

    def generate_summary(self, context: dict) -> dict:
        todos = context.get('todos', [])
        completed = sum(1 for t in todos if t.get('status') == 'completed')
        total = len(todos)

        # Find next pending todo
        next_todo = None
        for todo in todos:
            if todo.get('status') in ('pending', 'in_progress'):
                next_todo = todo.get('content', '')[:50]
                break

        # Extract last message preview
        last_msg = context.get('last_assistant_message', '')
        if last_msg:
            # Remove system reminders
            import re
            last_msg = re.sub(r'<system-reminder>[\s\S]*?</system-reminder>', '', last_msg)
            last_msg = last_msg.strip()[:self.max_length]

        return {
            "current_task": context.get('original_goal', '')[:80],
            "progress_summary": f"已完成 {completed}/{total} 项" if total > 0 else "进行中",
            "pending_decision": context.get('pending_question'),
            "next_step": next_todo,
            "last_message_preview": last_msg
        }


class DisabledProvider(SummaryProvider):
    """
    No AI summary - returns raw user prompt and pending question.
    Used when summary AI is disabled in settings.
    """

    def __init__(self, config: dict):
        self.max_length = config.get('max_preview_length', 150)

    def generate_summary(self, context: dict) -> dict:
        import re

        # Get raw user message (last user prompt)
        last_user = context.get('last_user_message', '')
        if last_user:
            # Remove system reminders
            last_user = re.sub(r'<system-reminder>[\s\S]*?</system-reminder>', '', last_user)
            last_user = last_user.strip()

        # Get pending question (AI needs user assistance)
        pending_question = context.get('pending_question', '')

        # Get current in-progress todo
        todos = context.get('todos', [])
        in_progress_task = None
        for todo in todos:
            if todo.get('status') == 'in_progress':
                in_progress_task = todo.get('content', '')[:60]
                break

        completed = sum(1 for t in todos if t.get('status') == 'completed')
        total = len(todos)

        return {
            "mode": "raw",  # Flag for formatter to use raw display
            "user_prompt": last_user[:self.max_length] if last_user else None,
            "pending_question": pending_question[:self.max_length] if pending_question else None,
            "current_task": in_progress_task or context.get('original_goal', '')[:60],
            "progress_summary": f"{completed}/{total}" if total > 0 else None,
        }


class SummaryService:
    """Summary service - selects provider based on config"""

    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self._initialized = True
        self.config = self._load_config()
        self.provider = self._create_provider()

    def _load_config(self) -> dict:
        """Load configuration from file"""
        if CONFIG_PATH.exists():
            try:
                with open(CONFIG_PATH, 'r') as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError):
                pass
        return {}

    def _create_provider(self) -> SummaryProvider:
        """Create appropriate provider based on config"""
        summary_config = self.config.get('summary', {})
        provider_type = summary_config.get('provider', 'auto')

        # Check if explicitly disabled
        if provider_type == 'disabled' or summary_config.get('disabled'):
            return DisabledProvider(summary_config)

        # Auto-select logic
        if provider_type == 'auto':
            third_party = summary_config.get('third_party', {})
            if third_party.get('enabled') and third_party.get('api_key'):
                provider_type = 'third_party'
            elif summary_config.get('extraction_only', {}).get('enabled'):
                provider_type = 'extraction_only'
            else:
                # Default to disabled (raw display, no AI)
                provider_type = 'disabled'

        # Create provider
        if provider_type == 'third_party':
            return ThirdPartyProvider(summary_config.get('third_party', {}))
        elif provider_type == 'claude_session':
            return ClaudeSessionProvider(summary_config.get('claude_session', {}))
        elif provider_type == 'disabled':
            return DisabledProvider(summary_config)
        else:
            return ExtractionOnlyProvider(summary_config.get('extraction_only', {}))

    def summarize(self, context: dict) -> dict:
        """Generate summary for given context"""
        return self.provider.generate_summary(context)

    def reload_config(self):
        """Reload configuration and recreate provider"""
        self.config = self._load_config()
        self.provider = self._create_provider()


def get_summary_service() -> SummaryService:
    """Get singleton summary service instance"""
    return SummaryService()

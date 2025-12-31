#!/usr/bin/env python3
"""
Claude Agent Wrapper
Provides interface for calling LLM in non-interactive mode.

Supports multiple providers:
- claude_cli: Claude Code CLI with optional API profile (Anthropic-compatible)
- anthropic_api: Direct Anthropic Messages API call
- openai_api: OpenAI-compatible API call

API Profiles (~/.claude-hooks/api_profiles.json):
  - 支持 ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ANTHROPIC_MODEL 格式
  - Claude CLI 通过环境变量使用这些配置
"""
import subprocess
import json
import shutil
import os
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List
from pathlib import Path


# ============================================================================
# Configuration
# ============================================================================

API_PROFILES_PATH = Path.home() / '.claude-hooks' / 'api_profiles.json'


@dataclass
class AgentConfig:
    """Claude Agent configuration"""
    mode: str = "autonomous"          # autonomous | interactive
    timeout: int = 180                # Timeout in seconds
    output_format: str = "json"       # json | text
    max_turns: int = 10               # Maximum turns
    skip_permissions: bool = False    # Skip permission confirmation

    # Provider: claude_cli | anthropic_api | openai_api
    provider: str = "claude_cli"

    # API Profile name (from ~/.claude-hooks/api_profiles.json)
    # 如果设置，将从 profile 加载 API 配置
    api_profile: str = ""

    # Direct API settings (used when api_profile not set)
    api_base_url: str = ""
    api_key: str = ""
    model: str = ""
    max_tokens: int = 4096
    temperature: float = 0.7


def load_api_profile(profile_name: str) -> Optional[Dict[str, str]]:
    """
    Load API profile from ~/.claude-hooks/api_profiles.json

    Profile format:
    {
      "kimi": {
        "ANTHROPIC_BASE_URL": "https://api.moonshot.cn/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "sk-xxx",
        "ANTHROPIC_MODEL": "kimi-k2-thinking"
      }
    }
    """
    if not API_PROFILES_PATH.exists():
        return None

    try:
        with open(API_PROFILES_PATH) as f:
            profiles = json.load(f)
            return profiles.get(profile_name)
    except (json.JSONDecodeError, IOError):
        return None


def list_api_profiles() -> List[str]:
    """List available API profile names"""
    if not API_PROFILES_PATH.exists():
        return []

    try:
        with open(API_PROFILES_PATH) as f:
            profiles = json.load(f)
            return list(profiles.keys())
    except (json.JSONDecodeError, IOError):
        return []


# ============================================================================
# Claude Agent
# ============================================================================

class ClaudeAgent:
    """
    LLM Agent Wrapper

    使用方式:
    1. Claude CLI + API Profile (推荐)
       agent = ClaudeAgent(project_path, AgentConfig(api_profile="kimi"))

    2. Claude CLI (原生 Anthropic API)
       agent = ClaudeAgent(project_path)

    3. 直接 API 调用
       agent = ClaudeAgent(project_path, AgentConfig(
           provider="anthropic_api",
           api_base_url="https://api.moonshot.cn/anthropic",
           api_key="sk-xxx",
           model="kimi-k2"
       ))
    """

    def __init__(self, project_path: str, config: Optional[AgentConfig] = None):
        self.project_path = Path(project_path)
        self.config = config or AgentConfig()

        # Load API profile if specified
        if self.config.api_profile:
            profile = load_api_profile(self.config.api_profile)
            if profile:
                self._apply_profile(profile)

        # Find Claude CLI
        self._claude_path = self._find_claude()

    def _apply_profile(self, profile: Dict[str, str]):
        """Apply API profile settings"""
        # Anthropic format
        if 'ANTHROPIC_BASE_URL' in profile:
            self.config.api_base_url = profile.get('ANTHROPIC_BASE_URL', '')
            self.config.api_key = profile.get('ANTHROPIC_AUTH_TOKEN', '')
            self.config.model = profile.get('ANTHROPIC_MODEL', '')
        # OpenAI format (fallback)
        elif 'OPENAI_API_BASE' in profile:
            self.config.api_base_url = profile.get('OPENAI_API_BASE', '')
            self.config.api_key = profile.get('OPENAI_API_KEY', '')
            self.config.model = profile.get('OPENAI_MODEL', '')

    def _find_claude(self) -> Optional[str]:
        """Find Claude CLI executable"""
        paths = [
            shutil.which('claude'),
            '/usr/local/bin/claude',
            str(Path.home() / '.local' / 'bin' / 'claude'),
            str(Path.home() / '.nvm' / 'versions' / 'node' / 'v24.11.0' / 'bin' / 'claude'),
        ]
        for path in paths:
            if path and Path(path).exists():
                return path
        return None

    def is_available(self) -> bool:
        """Check if the agent is available"""
        if self.config.provider == 'claude_cli':
            return self._claude_path is not None
        else:
            return bool(self.config.api_base_url and self.config.api_key)

    def execute(self, prompt: str, context: Optional[Dict] = None) -> Dict[str, Any]:
        """
        Execute LLM Agent task

        Args:
            prompt: Task prompt (supports template variables)
            context: Context variables for template rendering

        Returns:
            {"success": True/False, "data": ..., "error": ...}
        """
        # Render template variables
        if context:
            prompt = self._render_template(prompt, context)

        if self.config.provider == 'claude_cli':
            return self._execute_claude_cli(prompt)
        elif self.config.provider == 'anthropic_api':
            return self._execute_anthropic_api(prompt)
        elif self.config.provider == 'openai_api':
            return self._execute_openai_api(prompt)
        else:
            return {"success": False, "error": f"Unknown provider: {self.config.provider}"}

    def _execute_claude_cli(self, prompt: str) -> Dict[str, Any]:
        """
        Execute using Claude Code CLI

        通过环境变量设置第三方 API:
        - ANTHROPIC_BASE_URL
        - ANTHROPIC_AUTH_TOKEN
        - ANTHROPIC_MODEL
        """
        if not self._claude_path:
            return {
                "success": False,
                "error": "Claude CLI not found. Please install claude-code."
            }

        # Build command
        cmd = [self._claude_path, "-p", prompt]

        if self.config.skip_permissions:
            cmd.append("--dangerously-skip-permissions")

        # Prepare environment with API profile
        env = os.environ.copy()
        if self.config.api_base_url:
            env['ANTHROPIC_BASE_URL'] = self.config.api_base_url
        if self.config.api_key:
            env['ANTHROPIC_AUTH_TOKEN'] = self.config.api_key
        if self.config.model:
            env['ANTHROPIC_MODEL'] = self.config.model
        # Disable non-essential traffic for third-party APIs
        if self.config.api_base_url:
            env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1'

        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.project_path),
                capture_output=True,
                text=True,
                timeout=self.config.timeout,
                env=env
            )

            if result.returncode != 0:
                return {
                    "success": False,
                    "error": result.stderr or f"Exit code: {result.returncode}",
                    "raw_output": result.stdout
                }

            return self._parse_cli_output(result.stdout)

        except subprocess.TimeoutExpired:
            return {"success": False, "error": f"Timeout ({self.config.timeout}s)"}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def _execute_anthropic_api(self, prompt: str) -> Dict[str, Any]:
        """Execute using Anthropic Messages API directly"""
        if not self.config.api_base_url or not self.config.api_key:
            return {"success": False, "error": "API not configured"}

        try:
            import urllib.request
            import urllib.error

            url = f"{self.config.api_base_url.rstrip('/')}/messages"

            headers = {
                'Content-Type': 'application/json',
                'x-api-key': self.config.api_key,
                'anthropic-version': '2023-06-01',
            }

            data = {
                'model': self.config.model or 'claude-3-sonnet-20240229',
                'max_tokens': self.config.max_tokens,
                'messages': [{'role': 'user', 'content': prompt}]
            }

            req = urllib.request.Request(
                url,
                data=json.dumps(data).encode('utf-8'),
                headers=headers,
                method='POST'
            )

            with urllib.request.urlopen(req, timeout=self.config.timeout) as response:
                result = json.loads(response.read().decode('utf-8'))

            content = result.get('content', [{}])[0].get('text', '')
            return self._parse_text_output(content)

        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8') if e.fp else str(e)
            return {"success": False, "error": f"API error ({e.code}): {error_body}"}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def _execute_openai_api(self, prompt: str) -> Dict[str, Any]:
        """Execute using OpenAI-compatible API"""
        if not self.config.api_base_url or not self.config.api_key:
            return {"success": False, "error": "API not configured"}

        try:
            import urllib.request
            import urllib.error

            url = f"{self.config.api_base_url.rstrip('/')}/chat/completions"

            headers = {
                'Content-Type': 'application/json',
                'Authorization': f'Bearer {self.config.api_key}',
            }

            system_prompt = """You are an expert software engineer assistant.
When analyzing code or generating todos, respond in valid JSON format.
Be specific and actionable in your suggestions."""

            data = {
                'model': self.config.model or 'gpt-4',
                'messages': [
                    {'role': 'system', 'content': system_prompt},
                    {'role': 'user', 'content': prompt}
                ],
                'max_tokens': self.config.max_tokens,
                'temperature': self.config.temperature,
            }

            req = urllib.request.Request(
                url,
                data=json.dumps(data).encode('utf-8'),
                headers=headers,
                method='POST'
            )

            with urllib.request.urlopen(req, timeout=self.config.timeout) as response:
                result = json.loads(response.read().decode('utf-8'))

            content = result.get('choices', [{}])[0].get('message', {}).get('content', '')
            return self._parse_text_output(content)

        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8') if e.fp else str(e)
            return {"success": False, "error": f"API error ({e.code}): {error_body}"}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def _render_template(self, template: str, context: Dict) -> str:
        """Render template with context variables"""
        try:
            from jinja2 import Template, Environment, BaseLoader
            env = Environment(loader=BaseLoader())
            env.filters['tojson'] = lambda x: json.dumps(x, ensure_ascii=False)
            tmpl = env.from_string(template)
            return tmpl.render(**context)
        except ImportError:
            # Fallback to simple string replacement
            result = template
            for key, value in context.items():
                if isinstance(value, (dict, list)):
                    value = json.dumps(value, ensure_ascii=False)
                result = result.replace(f"{{{{ {key} }}}}", str(value))
                result = result.replace(f"{{{{{key}}}}}", str(value))
            return result

    def _parse_cli_output(self, output: str) -> Dict[str, Any]:
        """Parse Claude CLI output, extract JSON from text"""
        return self._parse_text_output(output)

    def _parse_text_output(self, output: str) -> Dict[str, Any]:
        """Parse text output, extract JSON result"""
        import re

        # 1. Try markdown JSON code block
        json_block_match = re.search(r'```json\s*([\s\S]*?)\s*```', output)
        if json_block_match:
            try:
                data = json.loads(json_block_match.group(1))
                return {"success": True, "data": data}
            except json.JSONDecodeError:
                pass

        # 2. Try generic code block
        code_block_match = re.search(r'```\s*([\s\S]*?)\s*```', output)
        if code_block_match:
            try:
                data = json.loads(code_block_match.group(1))
                return {"success": True, "data": data}
            except json.JSONDecodeError:
                pass

        # 3. Try bare JSON object (greedy match for nested objects)
        # Find the outermost { } pair
        brace_count = 0
        start_idx = -1
        end_idx = -1
        for i, char in enumerate(output):
            if char == '{':
                if brace_count == 0:
                    start_idx = i
                brace_count += 1
            elif char == '}':
                brace_count -= 1
                if brace_count == 0 and start_idx >= 0:
                    end_idx = i + 1
                    break

        if start_idx >= 0 and end_idx > start_idx:
            try:
                data = json.loads(output[start_idx:end_idx])
                return {"success": True, "data": data}
            except json.JSONDecodeError:
                pass

        # 4. Return raw output
        return {"success": True, "data": {"raw_output": output}}

    # ========================================================================
    # High-level methods
    # ========================================================================

    def analyze_project(self, task_context: str) -> Dict[str, Any]:
        """Analyze project structure for task decomposition"""
        prompt = f"""分析当前项目的代码结构，为以下任务提供分析:
{task_context}

请:
1. 识别项目类型和技术栈
2. 找到与任务相关的文件
3. 识别现有的代码模式
4. 建议实现方式

以 JSON 格式返回:
{{
  "project_type": "string",
  "tech_stack": ["list", "of", "techs"],
  "relevant_files": ["list", "of", "files"],
  "patterns": ["list", "of", "patterns"],
  "suggested_approach": "string"
}}
"""
        return self.execute(prompt)

    def generate_todos(self, task_title: str, task_description: str, analysis: Dict) -> Dict[str, Any]:
        """Generate todo list from task and analysis"""
        prompt = f"""根据以下任务和项目分析，生成具体可执行的 todo 列表。

任务: {task_title}
描述: {task_description}

项目分析:
{json.dumps(analysis, ensure_ascii=False, indent=2)}

生成 JSON 格式的 todos:
{{
  "todos": [
    {{
      "title": "简短的任务标题 (动词开头)",
      "description": "详细描述",
      "priority": 0,
      "estimated_minutes": 60,
      "files_involved": ["相关文件"]
    }}
  ],
  "execution_order": [0, 1, 2],
  "total_estimated_hours": 8.5
}}

要求:
- 每个 todo 应该是独立可完成的
- 使用动词开头: 创建, 编写, 添加, 实现, 测试等
- 包含具体的文件或模块引用
"""
        return self.execute(prompt)


# ============================================================================
# Factory function
# ============================================================================

def create_agent(
    project_path: str,
    api_profile: str = None,
    provider: str = "claude_cli",
    **kwargs
) -> ClaudeAgent:
    """
    Factory function to create an agent

    Args:
        project_path: Project directory path
        api_profile: Name of API profile from ~/.claude-hooks/api_profiles.json
        provider: 'claude_cli', 'anthropic_api', or 'openai_api'
        **kwargs: Additional AgentConfig parameters

    Returns:
        Configured ClaudeAgent instance

    Example:
        # Use kimi profile with Claude CLI
        agent = create_agent("/path/to/project", api_profile="kimi")

        # Direct API call
        agent = create_agent("/path/to/project",
            provider="anthropic_api",
            api_base_url="https://api.moonshot.cn/anthropic",
            api_key="sk-xxx",
            model="kimi-k2"
        )
    """
    config = AgentConfig(provider=provider, api_profile=api_profile or "", **kwargs)
    return ClaudeAgent(project_path, config)

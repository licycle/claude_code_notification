#!/usr/bin/env python3
"""
MCP Server Configuration

Configuration structure (in ~/.claude-task-tracker/config.json):
{
  "todo": {
    "enabled": true,
    "mcp_server": {
      "enabled": true,
      "host": "127.0.0.1",
      "port": 8765,
      "auto_start": true
    },
    "ai_decompose": {
      "enabled": true,
      "provider": "third_party"  // or "claude_cli"
    },
    "ai_summary": {
      "enabled": true,
      "provider": "third_party"
    }
  },
  "task_decomposition": {
    "enabled": true,
    "claude_integration": {
      "method": "cli",
      "timeout_seconds": 180,
      "max_retries": 2
    },
    "analysis": {
      "include_dependencies": true,
      "include_tests": true,
      "max_files_to_analyze": 50
    },
    "todo_generation": {
      "min_todos": 2,
      "max_todos": 20,
      "require_time_estimate": true
    },
    "confirmation": {
      "required": true,
      "auto_approve_threshold": 5
    }
  },
  "summary": {
    "provider": "third_party",  // or "disabled"
    "third_party": {
      "enabled": true,
      // Option 1: Use saved API profile (from claude-api)
      "profile": "moonshot",  // Profile name from ~/.claude-hooks/api_profiles.json
      // Option 2: Direct configuration
      "base_url": "https://api.openai.com/v1",
      "api_key": "sk-...",
      "model": "gpt-4",
      "max_tokens": 4096,
      "temperature": 0.7
    }
  }
}

Note: API profiles are managed by `claude-api` command:
  claude-api add moonshot OPENAI_API_BASE=https://api.moonshot.ai/v1 OPENAI_API_KEY=sk-xxx
  claude-api list
"""
import json
from pathlib import Path
from typing import Dict, Any, Optional, List

# Default configuration
DEFAULT_CONFIG = {
    'host': '127.0.0.1',
    'port': 8765,
    'auto_start': True,
    'log_level': 'INFO',
}

CONFIG_DIR = Path.home() / '.claude-task-tracker'
CONFIG_FILE = CONFIG_DIR / 'config.json'


def get_full_config() -> Dict[str, Any]:
    """Get full configuration from config file"""
    config = {
        'todo': {
            'enabled': True,
            'mcp_server': DEFAULT_CONFIG.copy(),
            'ai_decompose': {'enabled': False, 'provider': 'claude_cli'},
            'ai_summary': {'enabled': False, 'provider': 'disabled'},
        },
        'task_decomposition': {
            'enabled': True,
            'claude_integration': {
                'method': 'cli',
                'timeout_seconds': 180,
                'max_retries': 2
            },
            'analysis': {
                'include_dependencies': True,
                'include_tests': True,
                'max_files_to_analyze': 50
            },
            'todo_generation': {
                'min_todos': 2,
                'max_todos': 20,
                'require_time_estimate': True
            },
            'confirmation': {
                'required': True,
                'auto_approve_threshold': 5
            }
        },
        'summary': {
            'provider': 'disabled',
            'third_party': {
                'enabled': False,
                'base_url': '',
                'api_key': '',
                'model': 'gpt-4',
                'max_tokens': 4096,
                'temperature': 0.7
            }
        }
    }

    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE) as f:
                user_config = json.load(f)
                # Deep merge user config
                _deep_merge(config, user_config)
        except (json.JSONDecodeError, IOError):
            pass

    return config


def _deep_merge(base: Dict, override: Dict) -> None:
    """Deep merge override into base dict"""
    for key, value in override.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            _deep_merge(base[key], value)
        else:
            base[key] = value


def get_mcp_config() -> Dict[str, Any]:
    """Get MCP server configuration"""
    full_config = get_full_config()
    return full_config.get('todo', {}).get('mcp_server', DEFAULT_CONFIG.copy())


def get_server_url() -> str:
    """Get MCP server URL"""
    config = get_mcp_config()
    return f"http://{config['host']}:{config['port']}/mcp"


def is_server_enabled() -> bool:
    """Check if MCP server is enabled"""
    full_config = get_full_config()
    return full_config.get('todo', {}).get('mcp_server', {}).get('enabled', True)


def get_ai_config() -> Dict[str, Any]:
    """Get AI/LLM configuration for agent operations

    Supports multiple sources:
    1. Direct configuration in config.json (summary.third_party)
    2. API profile reference (summary.third_party.profile)
    """
    full_config = get_full_config()

    ai_config = {
        'provider': 'claude_cli',
        'third_party': {
            'enabled': False,
            'base_url': '',
            'api_key': '',
            'model': 'gpt-4',
            'max_tokens': 4096,
            'temperature': 0.7
        }
    }

    # Check ai_decompose settings
    todo_config = full_config.get('todo', {})
    ai_decompose = todo_config.get('ai_decompose', {})
    if ai_decompose.get('enabled') and ai_decompose.get('provider') == 'third_party':
        ai_config['provider'] = 'third_party'

    # Get third_party settings from summary config
    summary_config = full_config.get('summary', {})
    third_party = summary_config.get('third_party', {})

    if third_party.get('enabled'):
        # Check if using an API profile
        profile_name = third_party.get('profile')
        if profile_name:
            # Load from API profiles
            profile = get_api_profile(profile_name)
            if profile:
                ai_config['third_party'] = {
                    'enabled': True,
                    'base_url': profile.get('OPENAI_API_BASE', profile.get('base_url', '')),
                    'api_key': profile.get('OPENAI_API_KEY', profile.get('api_key', '')),
                    'model': profile.get('OPENAI_MODEL', third_party.get('model', 'gpt-4')),
                    'max_tokens': third_party.get('max_tokens', 4096),
                    'temperature': third_party.get('temperature', 0.7)
                }
            else:
                # Profile not found, fallback to direct config
                ai_config['third_party'] = {
                    'enabled': True,
                    'base_url': third_party.get('base_url', ''),
                    'api_key': third_party.get('api_key', ''),
                    'model': third_party.get('model', 'gpt-4'),
                    'max_tokens': third_party.get('max_tokens', 4096),
                    'temperature': third_party.get('temperature', 0.7)
                }
        else:
            # Direct configuration
            ai_config['third_party'] = {
                'enabled': True,
                'base_url': third_party.get('base_url', ''),
                'api_key': third_party.get('api_key', ''),
                'model': third_party.get('model', 'gpt-4'),
                'max_tokens': third_party.get('max_tokens', 4096),
                'temperature': third_party.get('temperature', 0.7)
            }

    return ai_config


def get_api_profile(name: str) -> Optional[Dict[str, str]]:
    """Load an API profile from ~/.claude-hooks/api_profiles.json

    API profiles are managed by claude-api command and contain
    environment variables like OPENAI_API_KEY, OPENAI_API_BASE, etc.
    """
    api_profiles_file = Path.home() / '.claude-hooks' / 'api_profiles.json'

    if not api_profiles_file.exists():
        return None

    try:
        with open(api_profiles_file) as f:
            profiles = json.load(f)
            return profiles.get(name)
    except (json.JSONDecodeError, IOError):
        return None


def list_api_profiles() -> List[str]:
    """List available API profile names"""
    api_profiles_file = Path.home() / '.claude-hooks' / 'api_profiles.json'

    if not api_profiles_file.exists():
        return []

    try:
        with open(api_profiles_file) as f:
            profiles = json.load(f)
            return list(profiles.keys())
    except (json.JSONDecodeError, IOError):
        return []


def get_task_decomposition_config() -> Dict[str, Any]:
    """Get task decomposition configuration"""
    full_config = get_full_config()
    return full_config.get('task_decomposition', {})


def save_config(config: Dict[str, Any]) -> bool:
    """Save configuration to file"""
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        return True
    except IOError:
        return False


def update_config(path: str, value: Any) -> bool:
    """Update a specific config value by dot-notation path

    Example: update_config('summary.third_party.api_key', 'sk-...')
    """
    config = get_full_config()

    keys = path.split('.')
    current = config
    for key in keys[:-1]:
        if key not in current:
            current[key] = {}
        current = current[key]

    current[keys[-1]] = value
    return save_config(config)

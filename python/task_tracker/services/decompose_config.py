#!/usr/bin/env python3
"""
decompose_config.py - Shared configuration for project decomposition

Provides unified prompt templates and settings for both Python and Swift decomposers.
Configuration is loaded from ~/.claude-hooks/decompose_config.json
"""
import json
from pathlib import Path
from typing import List, Dict, Any, Optional

from task_tracker.hooks.utils import log


# ============================================================================
# Configuration Paths
# ============================================================================

CONFIG_PATH = Path.home() / '.claude-hooks' / 'decompose_config.json'


# ============================================================================
# Default Values
# ============================================================================

DEFAULT_ALLOWED_TOOLS = [
    'Task',       # Explore subagent for deep search
    'Read',       # Read files
    'Glob',       # File pattern matching
    'Grep',       # Content search
    'LS',         # Directory listing
    'WebSearch',  # Web search for docs
    'WebFetch',   # Fetch web content
    'TodoWrite',  # Create todos (triggers hook sync)
]

DEFAULT_PROMPT_TEMPLATE = """You are an expert software engineer. Analyze the codebase and decompose the given task into actionable todos.

## Task
{task_title}

## Project Paths
{project_paths_list}

## Instructions

1. **Explore the codebase (READ-ONLY):**
   - Use Task tool with subagent_type="Explore" for deep search
   - Use Glob to find relevant files by pattern
   - Use Grep to search for code patterns
   - Use Read to examine key files
   - Use LS to understand directory structure

2. **Output todos using TodoWrite tool:**
   - Atomic and independently completable
   - Start with action verbs (Implement, Add, Fix, Refactor, Test, Create, Update)
   - Reference specific files or modules
   - Include both `content` and `activeForm` fields
   - Status should be "pending"

## CRITICAL RESTRICTIONS
- DO NOT modify any files
- DO NOT execute any code
- ONLY analyze and create todos
- You MUST use TodoWrite as your final output
"""


# ============================================================================
# Configuration Loading
# ============================================================================

_cached_config: Optional[Dict[str, Any]] = None


def load_decompose_config(force_reload: bool = False) -> Dict[str, Any]:
    """
    Load decompose configuration from JSON file.

    Returns default values if file doesn't exist or is invalid.
    Results are cached for performance.
    """
    global _cached_config

    if _cached_config is not None and not force_reload:
        return _cached_config

    config = {
        'prompt_template': DEFAULT_PROMPT_TEMPLATE,
        'allowed_tools': DEFAULT_ALLOWED_TOOLS,
    }

    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH) as f:
                user_config = json.load(f)

            # Merge user config with defaults
            if 'prompt_template' in user_config:
                config['prompt_template'] = user_config['prompt_template']
            if 'allowed_tools' in user_config:
                config['allowed_tools'] = user_config['allowed_tools']

            log("DECOMPOSE_CONFIG", f"Loaded config from {CONFIG_PATH}")
        except (json.JSONDecodeError, IOError) as e:
            log("DECOMPOSE_CONFIG", f"Failed to load config: {e}, using defaults")
    else:
        log("DECOMPOSE_CONFIG", f"Config not found at {CONFIG_PATH}, using defaults")

    _cached_config = config
    return config


# ============================================================================
# Configuration Accessors
# ============================================================================

def get_prompt_template() -> str:
    """Get the decompose prompt template"""
    config = load_decompose_config()
    return config['prompt_template']


def get_allowed_tools() -> List[str]:
    """Get the list of allowed tools for decomposition"""
    config = load_decompose_config()
    return config['allowed_tools']


def get_allowed_tools_string() -> str:
    """Get allowed tools as comma-separated string"""
    return ','.join(get_allowed_tools())


def build_prompt(task_title: str, project_paths: List[str]) -> str:
    """
    Build the decompose prompt with task details filled in.

    Args:
        task_title: Title of the task
        project_paths: List of project paths to analyze

    Returns:
        Formatted prompt string
    """
    template = get_prompt_template()
    project_paths_list = "\n".join(f"- {p}" for p in project_paths)

    return template.format(
        task_title=task_title,
        project_paths_list=project_paths_list
    )

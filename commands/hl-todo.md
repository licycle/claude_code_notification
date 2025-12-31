---
description: "Load project todos and execute them"
---

# /hl-todo - Project Todo Executor

Load and execute todos for the current project.

## Usage

```
/hl-todo              # List todos and start the first pending one
/hl-todo next         # Execute the next pending todo
/hl-todo <id>         # Execute a specific todo by ID
```

## Instructions

First, use the MCP tool `list_todos` to get all pending todos for the current project:

```
Use the list_todos MCP tool to get todos for this project.
```

Then, based on the user's request:

### Default (no args or "list")
1. Display the list of pending todos with their IDs and titles
2. Ask the user which todo they want to start, or offer to start the first one
3. When user confirms, call `start_todo` MCP tool with the selected todo ID
4. Read the todo details and begin executing the task described

### With "next"
1. Get the first pending todo from `list_todos`
2. Call `start_todo` to mark it as in_progress
3. Begin executing the task

### With specific ID
1. Call `get_todo` MCP tool with the provided ID
2. Call `start_todo` to mark it as in_progress
3. Begin executing the task

## During Execution

When working on a todo:
1. Follow the todo's title and description as the task specification
2. Work through the task step by step
3. When finished, call `complete_todo` MCP tool with a brief summary

## Example Workflow

```
User: /hl-todo

Claude: Let me check the pending todos for this project...
[Uses list_todos MCP tool]

Found 3 pending todos:
1. #42 - Add user authentication middleware
2. #43 - Write unit tests for auth module
3. #44 - Update API documentation

Would you like me to start with #42 (Add user authentication middleware)?

User: yes

Claude: Starting todo #42...
[Uses start_todo MCP tool]

I'll now implement the user authentication middleware...
[Works on the task]

Done! Let me mark this as complete.
[Uses complete_todo MCP tool with summary]

Todo #42 completed. Would you like to continue with the next todo (#43)?
```

## MCP Tools Used

- `list_todos` - Get pending todos for project
- `get_todo` - Get details of a specific todo
- `start_todo` - Mark todo as in_progress
- `complete_todo` - Mark todo as completed with summary
- `split_todo` - Split a todo into sub-tasks if needed

$ARGUMENTS

import Foundation

/// Shared configuration for project decomposition
/// Reads from ~/.claude-hooks/decompose_config.json
class DecomposeConfig {
    static let shared = DecomposeConfig()

    private let configPath: URL
    private var cachedConfig: [String: Any]?

    // MARK: - Default Values

    static let defaultAllowedTools = [
        "Task",       // Explore subagent for deep search
        "Read",       // Read files
        "Glob",       // File pattern matching
        "Grep",       // Content search
        "LS",         // Directory listing
        "WebSearch",  // Web search for docs
        "WebFetch",   // Fetch web content
        "TodoWrite",  // Create todos (triggers hook sync)
    ]

    static let defaultPromptTemplate = """
You are an expert software engineer. Analyze the codebase and decompose the given task into actionable todos.

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

    // MARK: - Initialization

    private init() {
        configPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude-hooks")
            .appendingPathComponent("decompose_config.json")
    }

    // MARK: - Configuration Loading

    /// Load configuration from JSON file
    func loadConfig(forceReload: Bool = false) -> [String: Any] {
        if let cached = cachedConfig, !forceReload {
            return cached
        }

        var config: [String: Any] = [
            "prompt_template": Self.defaultPromptTemplate,
            "allowed_tools": Self.defaultAllowedTools
        ]

        if FileManager.default.fileExists(atPath: configPath.path) {
            do {
                let data = try Data(contentsOf: configPath)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let template = json["prompt_template"] as? String {
                        config["prompt_template"] = template
                    }
                    if let tools = json["allowed_tools"] as? [String] {
                        config["allowed_tools"] = tools
                    }
                }
                log("DecomposeConfig: Loaded from \(configPath.path)")
            } catch {
                log("DecomposeConfig: Failed to load: \(error), using defaults")
            }
        } else {
            log("DecomposeConfig: Not found at \(configPath.path), using defaults")
        }

        cachedConfig = config
        return config
    }

    // MARK: - Accessors

    /// Get the prompt template
    var promptTemplate: String {
        let config = loadConfig()
        return config["prompt_template"] as? String ?? Self.defaultPromptTemplate
    }

    /// Get allowed tools as array
    var allowedTools: [String] {
        let config = loadConfig()
        return config["allowed_tools"] as? [String] ?? Self.defaultAllowedTools
    }

    /// Get allowed tools as comma-separated string
    var allowedToolsString: String {
        return allowedTools.joined(separator: ",")
    }

    // MARK: - Prompt Building

    /// Build the decompose prompt with task details
    func buildPrompt(taskTitle: String, projectPaths: [String]) -> String {
        let template = promptTemplate
        let pathsList = projectPaths.map { "- \($0)" }.joined(separator: "\n")

        return template
            .replacingOccurrences(of: "{task_title}", with: taskTitle)
            .replacingOccurrences(of: "{project_paths_list}", with: pathsList)
    }
}

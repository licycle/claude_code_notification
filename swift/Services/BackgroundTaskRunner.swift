import Foundation

/// Notification posted when a background task completes
extension Notification.Name {
    static let backgroundTaskCompleted = Notification.Name("BackgroundTaskCompleted")
}

/// Manages background process execution for task decomposition
class BackgroundTaskRunner {
    static let shared = BackgroundTaskRunner()

    private var runningTasks: [Int: Process] = [:]
    private let queue = DispatchQueue(label: "com.claudemonitor.background-tasks", qos: .background)

    private init() {}

    /// Run task decomposition in background by directly calling claude CLI
    /// - Parameters:
    ///   - taskId: The global task ID to decompose
    ///   - projects: List of project paths to analyze
    ///   - apiProfile: Optional API profile to use (e.g., "kimi", "aws")
    ///   - accountAlias: Optional account alias to use (e.g., "c1", "c2")
    ///   - completion: Called when decomposition completes with success/failure
    func runDecompose(
        taskId: Int,
        projects: [String],
        apiProfile: String? = nil,
        accountAlias: String? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        log("BackgroundTaskRunner: runDecompose called for task \(taskId)")
        log("BackgroundTaskRunner: projects = \(projects)")
        log("BackgroundTaskRunner: apiProfile = \(apiProfile ?? "nil")")
        log("BackgroundTaskRunner: accountAlias = \(accountAlias ?? "default")")

        queue.async { [weak self] in
            guard let self = self else { return }

            let process = Process()

            // Build the decompose prompt
            let prompt = self.buildDecomposePrompt(taskId: taskId, projects: projects)

            // Find claude executable - try common locations
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            let claudePaths = [
                "\(homePath)/.nvm/versions/node/v24.11.0/bin/claude",
                "\(homePath)/.local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"
            ]

            var claudePath: String? = nil
            for path in claudePaths {
                if FileManager.default.fileExists(atPath: path) {
                    claudePath = path
                    break
                }
            }

            guard let execPath = claudePath else {
                log("BackgroundTaskRunner: claude executable not found")
                DispatchQueue.main.async {
                    completion(false, "claude executable not found in common locations")
                }
                return
            }

            log("BackgroundTaskRunner: Using claude at: \(execPath)")

            // Call claude directly with -p flag and allowed tools for decomposition
            process.executableURL = URL(fileURLWithPath: execPath)
            let allowedTools = "Read,Glob,Grep,LS,WebSearch,WebFetch,TodoWrite"
            process.arguments = ["-p", prompt, "--allowedTools", allowedTools, "--max-turns", "15"]

            // Set working directory to first project if available
            let workingDir = projects.first ?? FileManager.default.homeDirectoryForCurrentUser.path
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)

            // Build environment
            var env = ProcessInfo.processInfo.environment

            // Ensure PATH includes common locations (for tools claude might call)
            let defaultPaths = [
                "\(homePath)/.local/bin",
                "\(homePath)/.nvm/versions/node/v24.11.0/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin"
            ].joined(separator: ":")
            env["PATH"] = "\(defaultPaths):\(env["PATH"] ?? "")"
            env["HOME"] = homePath
            env["SHELL"] = "/bin/zsh"
            env["PWD"] = workingDir

            // Load API profile environment variables if specified
            if let profile = apiProfile, !profile.isEmpty {
                if let profileEnv = APIProfileManager.shared.getProfileEnv(name: profile) {
                    for (key, value) in profileEnv {
                        env[key] = value
                        log("BackgroundTaskRunner: Set env \(key)=\(key.contains("TOKEN") ? "***" : value)")
                    }
                } else {
                    log("BackgroundTaskRunner: WARNING - API profile '\(profile)' not found")
                }
            }

            // Set Claude config directory based on account alias
            if let alias = accountAlias {
                env["CLAUDE_ACCOUNT_ALIAS"] = alias
                if let configDir = AccountManager.shared.getConfigDir(for: alias) {
                    env["CLAUDE_CONFIG_DIR"] = configDir
                    log("BackgroundTaskRunner: Using config dir: \(configDir)")
                }
            } else {
                env["CLAUDE_ACCOUNT_ALIAS"] = "default"
            }

            // Set Claude Monitor environment variables for session tracking
            env["CLAUDE_PENDING_SESSION_ID"] = UUID().uuidString
            env["CLAUDE_TERM_BUNDLE_ID"] = "com.claude.monitor"
            env["CLAUDE_TERM_PID"] = String(ProcessInfo.processInfo.processIdentifier)
            env["CLAUDE_SHELL_PID"] = String(ProcessInfo.processInfo.processIdentifier)
            env["CLAUDE_CG_WINDOW_ID"] = "0"

            // Set global task ID for decompose session (used by progress_tracker.py)
            env["CLAUDE_DECOMPOSE_TASK_ID"] = String(taskId)

            process.environment = env
            log("BackgroundTaskRunner: Environment configured, starting process...")

            // Get the pending session ID for cleanup later
            let pendingId = env["CLAUDE_PENDING_SESSION_ID"] ?? ""

            // Call session_init.py to create pending session BEFORE starting Claude
            self.callSessionInit(env: env)

            // Capture output
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Store reference
            self.runningTasks[taskId] = process

            do {
                try process.run()
                process.waitUntilExit()

                // Call session_cleanup.py AFTER Claude exits
                self.callSessionCleanup(pendingId: pendingId, env: env)

                let exitCode = process.terminationStatus
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                // Remove from running tasks
                self.runningTasks.removeValue(forKey: taskId)

                // Notify on main thread
                DispatchQueue.main.async {
                    if exitCode == 0 {
                        log("BackgroundTaskRunner: Task \(taskId) completed successfully")
                        completion(true, output)
                    } else {
                        log("BackgroundTaskRunner: Task \(taskId) failed with exit code \(exitCode)")
                        log("BackgroundTaskRunner: stderr = \(errorOutput)")
                        log("BackgroundTaskRunner: stdout = \(output)")
                        let message = errorOutput.isEmpty ? "Exit code: \(exitCode)" : errorOutput
                        completion(false, message)
                    }

                    // Post notification
                    NotificationCenter.default.post(
                        name: .backgroundTaskCompleted,
                        object: nil,
                        userInfo: [
                            "taskId": taskId,
                            "success": exitCode == 0,
                            "output": output
                        ]
                    )
                }

            } catch {
                self.runningTasks.removeValue(forKey: taskId)

                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    /// Check if a task is currently running
    func isRunning(taskId: Int) -> Bool {
        return runningTasks[taskId] != nil
    }

    /// Cancel a running task
    func cancel(taskId: Int) {
        if let process = runningTasks[taskId] {
            process.terminate()
            runningTasks.removeValue(forKey: taskId)
        }
    }

    /// Cancel all running tasks
    func cancelAll() {
        for (_, process) in runningTasks {
            process.terminate()
        }
        runningTasks.removeAll()
    }

    // MARK: - Private Helpers

    /// Call session_init.py to create pending session before Claude starts
    private func callSessionInit(env: [String: String]) {
        let hooksBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-hooks")
        let scriptPath = hooksBase
            .appendingPathComponent("task_tracker")
            .appendingPathComponent("hooks")
            .appendingPathComponent("session_init.py")

        guard FileManager.default.fileExists(atPath: scriptPath.path) else {
            log("BackgroundTaskRunner: session_init.py not found at \(scriptPath.path)")
            return
        }

        // Build environment with PYTHONPATH
        var scriptEnv = env
        scriptEnv["PYTHONPATH"] = hooksBase.path

        let initProcess = Process()
        initProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        initProcess.arguments = [scriptPath.path]
        initProcess.environment = scriptEnv
        initProcess.currentDirectoryURL = URL(fileURLWithPath: env["PWD"] ?? hooksBase.path)
        initProcess.standardOutput = FileHandle.nullDevice
        initProcess.standardError = FileHandle.nullDevice

        do {
            try initProcess.run()
            initProcess.waitUntilExit()
            log("BackgroundTaskRunner: session_init.py completed with exit code \(initProcess.terminationStatus)")
        } catch {
            log("BackgroundTaskRunner: session_init.py failed: \(error)")
        }
    }

    /// Call session_cleanup.py to cleanup session after Claude exits
    private func callSessionCleanup(pendingId: String, env: [String: String]) {
        let hooksBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-hooks")
        let scriptPath = hooksBase
            .appendingPathComponent("task_tracker")
            .appendingPathComponent("hooks")
            .appendingPathComponent("session_cleanup.py")

        guard FileManager.default.fileExists(atPath: scriptPath.path) else {
            log("BackgroundTaskRunner: session_cleanup.py not found at \(scriptPath.path)")
            return
        }

        // Build environment with PYTHONPATH
        var scriptEnv = env
        scriptEnv["PYTHONPATH"] = hooksBase.path

        let cleanupProcess = Process()
        cleanupProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        cleanupProcess.arguments = [scriptPath.path, pendingId]
        cleanupProcess.environment = scriptEnv
        cleanupProcess.standardOutput = FileHandle.nullDevice
        cleanupProcess.standardError = FileHandle.nullDevice

        do {
            try cleanupProcess.run()
            // Don't wait - run in background like shell wrapper does
            log("BackgroundTaskRunner: session_cleanup.py started for pending_id=\(pendingId)")
        } catch {
            log("BackgroundTaskRunner: session_cleanup.py failed: \(error)")
        }
    }

    /// Build the decompose prompt for Claude CLI
    private func buildDecomposePrompt(taskId: Int, projects: [String]) -> String {
        // Get task info from database
        guard let task = TodoDatabaseManager.shared.getGlobalTask(id: taskId) else {
            log("BackgroundTaskRunner: Could not find task \(taskId), using default prompt")
            return "Analyze project structure and suggest actionable todos using the TodoWrite tool."
        }

        let projectList = projects.map { "- \($0)" }.joined(separator: "\n")

        // Use prompt that requires TodoWrite tool (not JSON output)
        // This allows PostToolUse hook to automatically capture todos
        let prompt = """
You are an expert software engineer. Analyze the following project(s) and decompose the given task into actionable todos.

## Task
Title: \(task.title)
Description: \(task.description ?? "No description provided")

## Project Paths
\(projectList)

## Instructions

1. **Explore the codebase thoroughly:**
   - Use Glob to find relevant files by pattern
   - Use Grep to search for code patterns and keywords
   - Use Read to examine key files in detail

2. **Based on your analysis, use the TodoWrite tool** to create todos that:
   - Are atomic and independently completable
   - Start with action verbs (Implement, Add, Fix, Refactor, Test, Create, Update)
   - Reference specific files or modules when possible
   - Include both `content` (what to do) and `activeForm` (doing what) fields

## Requirements
- Each todo should be atomic and independently completable
- Status should be "pending" for new todos

## Example TodoWrite call:
```
TodoWrite with todos=[
  {"content": "Implement user authentication in auth.py", "status": "pending", "activeForm": "Implementing user authentication"},
  {"content": "Add unit tests for auth module", "status": "pending", "activeForm": "Adding unit tests"}
]
```

IMPORTANT: You MUST use the TodoWrite tool to create the todo list.
"""
        return prompt
    }
}

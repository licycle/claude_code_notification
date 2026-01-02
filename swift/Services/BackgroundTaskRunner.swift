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

            // Build the decompose prompt using shared config
            let taskTitle = self.getTaskTitle(taskId: taskId)
            let prompt = DecomposeConfig.shared.buildPrompt(taskTitle: taskTitle, projectPaths: projects)

            // Find claude executable using PathConstants
            let claudePaths = PathConstants.claudeSearchPaths

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

            // Call claude directly with -p flag and allowed tools from shared config
            process.executableURL = URL(fileURLWithPath: execPath)
            process.arguments = ["-p", prompt, "--allowedTools", DecomposeConfig.shared.allowedToolsString]

            // Set working directory to first project if available
            let workingDir = projects.first ?? FileManager.default.homeDirectoryForCurrentUser.path
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)

            // Build environment
            var env = ProcessInfo.processInfo.environment

            // Ensure PATH includes common locations (for tools claude might call)
            let defaultPaths = PathConstants.defaultPathEnv
            env["PATH"] = "\(defaultPaths):\(env["PATH"] ?? "")"
            env["HOME"] = PathConstants.home
            env["SHELL"] = PathConstants.currentShell
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
        let hooksBaseURL = URL(fileURLWithPath: PathConstants.hooksBase)
        let scriptPath = URL(fileURLWithPath: PathConstants.taskTrackerHooksDir)
            .appendingPathComponent("session_init.py")

        guard FileManager.default.fileExists(atPath: scriptPath.path) else {
            log("BackgroundTaskRunner: session_init.py not found at \(scriptPath.path)")
            return
        }

        // Build environment with PYTHONPATH
        var scriptEnv = env
        scriptEnv["PYTHONPATH"] = hooksBaseURL.path

        let initProcess = Process()
        initProcess.executableURL = URL(fileURLWithPath: PathConstants.findPython3())
        initProcess.arguments = [scriptPath.path]
        initProcess.environment = scriptEnv
        initProcess.currentDirectoryURL = URL(fileURLWithPath: env["PWD"] ?? hooksBaseURL.path)
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
        let hooksBaseURL = URL(fileURLWithPath: PathConstants.hooksBase)
        let scriptPath = URL(fileURLWithPath: PathConstants.taskTrackerHooksDir)
            .appendingPathComponent("session_cleanup.py")

        guard FileManager.default.fileExists(atPath: scriptPath.path) else {
            log("BackgroundTaskRunner: session_cleanup.py not found at \(scriptPath.path)")
            return
        }

        // Build environment with PYTHONPATH
        var scriptEnv = env
        scriptEnv["PYTHONPATH"] = hooksBaseURL.path

        let cleanupProcess = Process()
        cleanupProcess.executableURL = URL(fileURLWithPath: PathConstants.findPython3())
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

    /// Get task title from database
    private func getTaskTitle(taskId: Int) -> String {
        guard let task = TodoDatabaseManager.shared.getGlobalTask(id: taskId) else {
            log("BackgroundTaskRunner: Could not find task \(taskId)")
            return "Analyze project and create todos"
        }
        return task.title
    }
}

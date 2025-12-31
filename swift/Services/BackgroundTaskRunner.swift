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

    /// Run task decomposition in background
    /// - Parameters:
    ///   - taskId: The global task ID to decompose
    ///   - projects: List of project paths to analyze
    ///   - apiProfile: Optional API profile to use (e.g., "kimi")
    ///   - completion: Called when decomposition completes with success/failure
    func runDecompose(
        taskId: Int,
        projects: [String],
        apiProfile: String? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let process = Process()

            // Find python3 executable
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

            // Build arguments
            var args = ["python3", "-m", "task_tracker.cli.todo_cli", "task", "decompose", String(taskId)]

            if !projects.isEmpty {
                args.append("--projects")
                args.append(projects.joined(separator: ","))
            }

            if let profile = apiProfile {
                args.append("--api-profile")
                args.append(profile)
            }

            process.arguments = args

            // Set working directory to hooks location
            let hooksDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude-hooks")
            if FileManager.default.fileExists(atPath: hooksDir.path) {
                process.currentDirectoryURL = hooksDir
            }

            // Set environment
            var env = ProcessInfo.processInfo.environment
            env["PYTHONPATH"] = hooksDir.path
            process.environment = env

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
                        completion(true, output)
                    } else {
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
}

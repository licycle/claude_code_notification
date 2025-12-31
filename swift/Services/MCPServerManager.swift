import Foundation

/// Manages the MCP (Model Context Protocol) server lifecycle
/// The MCP server provides HTTP endpoints for Claude Code integration
class MCPServerManager {
    static let shared = MCPServerManager()

    private var process: Process?

    // Paths
    private let hooksDir = NSString(string: "~/.claude-hooks").expandingTildeInPath
    private let logDir = NSString(string: "~/.claude-task-tracker/logs").expandingTildeInPath
    private let pidFile = NSString(string: "~/.claude-task-tracker/mcp_server.pid").expandingTildeInPath

    private init() {}

    // MARK: - Public API

    /// Start the MCP server
    func start() {
        // Check if already running via PID file
        if running {
            log("MCPServerManager: Server already running (PID: \(pid ?? 0))")
            return
        }

        log("MCPServerManager: Starting MCP server...")

        // Ensure log directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logDir) {
            try? fileManager.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "task_tracker.mcp.server"]
        process.currentDirectoryURL = URL(fileURLWithPath: hooksDir)

        // Set environment variables
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = hooksDir
        env["CLAUDE_LOG_DIR"] = logDir
        process.environment = env

        // Redirect output to /dev/null to prevent blocking
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Handle termination
        process.terminationHandler = { proc in
            log("MCPServerManager: Server terminated with exit code \(proc.terminationStatus)")
        }

        do {
            try process.run()
            self.process = process
            log("MCPServerManager: Server started with PID \(process.processIdentifier)")
        } catch {
            log("MCPServerManager: Failed to start server - \(error.localizedDescription)")
        }
    }

    /// Stop the MCP server
    func stop() {
        // First try to stop our managed process
        if let process = process, process.isRunning {
            log("MCPServerManager: Stopping managed process (PID \(process.processIdentifier))...")
            process.terminate()
            self.process = nil
            return
        }

        // If no managed process, try to kill by PID file
        if let serverPid = readPidFromFile() {
            log("MCPServerManager: Stopping server by PID file (PID \(serverPid))...")
            kill(serverPid, SIGTERM)
            // Clean up PID file
            try? FileManager.default.removeItem(atPath: pidFile)
        } else {
            log("MCPServerManager: Server not running")
        }

        self.process = nil
    }

    /// Restart the MCP server
    func restart() {
        stop()
        // Brief delay to ensure port is released
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }

    /// Check if server is running by checking PID file and process
    var running: Bool {
        // First check our managed process
        if let process = process, process.isRunning {
            return true
        }

        // Check PID file
        guard let serverPid = readPidFromFile() else {
            return false
        }

        // Check if process is actually running
        return kill(serverPid, 0) == 0
    }

    /// Get server PID
    var pid: Int32? {
        // First check our managed process
        if let process = process, process.isRunning {
            return process.processIdentifier
        }

        // Check PID file
        return readPidFromFile()
    }

    // MARK: - Private Helpers

    private func readPidFromFile() -> Int32? {
        guard FileManager.default.fileExists(atPath: pidFile) else {
            return nil
        }

        guard let content = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        return pid
    }
}

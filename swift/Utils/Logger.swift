import Foundation

// MARK: - Global Logging System

let logPath = NSString(string: "~/.claude-hooks/swift_debug.log").expandingTildeInPath

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let entry = "[\(ts)] \(msg)\n"
    if let data = entry.data(using: .utf8) {
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        } else {
            try? entry.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}

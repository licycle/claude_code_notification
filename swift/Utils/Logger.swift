import Foundation

// MARK: - Global Logging System

let logPath = NSString(string: "~/.claude-hooks/swift_debug.log").expandingTildeInPath

// 使用本地时区的日期格式化器
private let logDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter
}()

func log(_ msg: String) {
    let ts = logDateFormatter.string(from: Date())
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

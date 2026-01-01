import Foundation

/// 集中管理路径常量和环境检测
enum PathConstants {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    // MARK: - 目录常量
    static let dataDir = "\(home)/.claude-task-tracker"
    static let hooksBase = "\(home)/.claude-hooks"
    static let taskTrackerHooksDir = "\(hooksBase)/task_tracker/hooks"

    // MARK: - 动态环境检测

    /// 动态查找 nvm 中的 node 版本目录
    static var nvmNodeBinPaths: [String] {
        let nvmDir = "\(home)/.nvm/versions/node"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) else {
            return []
        }
        // 按版本号降序，优先使用最新版本
        return versions
            .filter { $0.hasPrefix("v") }
            .sorted { compareVersions($0, $1) > 0 }
            .map { "\(nvmDir)/\($0)/bin" }
    }

    /// Claude 可执行文件搜索路径（动态生成）
    static var claudeSearchPaths: [String] {
        var paths = nvmNodeBinPaths.map { "\($0)/claude" }
        paths.append(contentsOf: [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ])
        return paths
    }

    /// 默认 PATH 环境变量（动态生成）
    static var defaultPathEnv: String {
        var paths = ["\(home)/.local/bin"]
        paths.append(contentsOf: nvmNodeBinPaths)
        paths.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])
        return paths.joined(separator: ":")
    }

    /// 当前用户 shell（从环境变量读取）
    static var currentShell: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// 查找 Python3 可执行文件
    static func findPython3() -> String {
        let candidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "/usr/bin/python3"
    }

    /// 版本号比较 (v20.0.0 vs v18.17.0)
    private static func compareVersions(_ a: String, _ b: String) -> Int {
        let aNum = a.dropFirst().split(separator: ".").compactMap { Int($0) }
        let bNum = b.dropFirst().split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aNum.count, bNum.count) {
            let av = i < aNum.count ? aNum[i] : 0
            let bv = i < bNum.count ? bNum[i] : 0
            if av != bv { return av - bv }
        }
        return 0
    }
}

import Foundation

// MARK: - Settings Configuration Manager

class SettingsManager {
    static let shared = SettingsManager()

    // Config file path - single source of truth for both Swift and Python
    private var configFilePath: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-task-tracker")
        return dir.appendingPathComponent("config.json")
    }

    // In-memory cache (loaded from config.json)
    private var _summaryEnabled: Bool = false
    private var _summaryBaseURL: String = ""
    private var _summaryAPIKey: String = ""
    private var _summaryModel: String = "gpt-3.5-turbo"

    var summaryEnabled: Bool {
        get { _summaryEnabled }
        set { _summaryEnabled = newValue }
    }

    var summaryBaseURL: String {
        get { _summaryBaseURL }
        set { _summaryBaseURL = newValue }
    }

    var summaryAPIKey: String {
        get { _summaryAPIKey }
        set { _summaryAPIKey = newValue }
    }

    var summaryModel: String {
        get { _summaryModel }
        set { _summaryModel = newValue }
    }

    private init() {
        loadFromFile()
    }

    /// Load config from config.json
    func loadFromFile() {
        guard FileManager.default.fileExists(atPath: configFilePath.path) else {
            log("Config file not found, using defaults")
            return
        }

        do {
            let data = try Data(contentsOf: configFilePath)
            guard let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            if let summary = config["summary"] as? [String: Any] {
                // Check if enabled
                let provider = summary["provider"] as? String ?? "disabled"
                _summaryEnabled = (provider == "third_party")

                // Load third_party config
                if let thirdParty = summary["third_party"] as? [String: Any] {
                    _summaryBaseURL = thirdParty["base_url"] as? String ?? ""
                    _summaryAPIKey = thirdParty["api_key"] as? String ?? ""
                    _summaryModel = thirdParty["model"] as? String ?? "gpt-3.5-turbo"
                }
            }

            log("Config loaded from \(configFilePath.path)")
        } catch {
            log("Failed to load config: \(error)")
        }
    }

    /// Save config to config.json (called explicitly by Save button)
    func saveToFile() {
        do {
            let dir = configFilePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // Read existing config to preserve other settings
            var config: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: configFilePath.path) {
                if let data = try? Data(contentsOf: configFilePath),
                   let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    config = existing
                }
            }

            // Build summary config
            var summaryConfig: [String: Any] = [:]

            if _summaryEnabled && !_summaryAPIKey.isEmpty {
                summaryConfig["provider"] = "third_party"
                summaryConfig["third_party"] = [
                    "enabled": true,
                    "base_url": _summaryBaseURL,
                    "api_key": _summaryAPIKey,
                    "model": _summaryModel,
                    "max_tokens": 500
                ]
            } else {
                summaryConfig["provider"] = "disabled"
                summaryConfig["disabled"] = true
            }

            config["summary"] = summaryConfig

            // Write config
            let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try data.write(to: configFilePath)

            log("Config saved to \(configFilePath.path)")
        } catch {
            log("Failed to save config: \(error)")
        }
    }
}

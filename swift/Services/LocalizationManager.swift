import Foundation

// MARK: - Localization Manager

class LocalizationManager {
    static let shared = LocalizationManager()

    // Notification for language change
    static let languageChangedNotification = Notification.Name("LocalizationManagerLanguageChanged")

    // Current language (persisted to config.json)
    private(set) var currentLanguage: Language = .english

    private init() {
        loadLanguagePreference()
    }

    // MARK: - Language Preference Persistence

    /// Load language preference from config.json
    func loadLanguagePreference() {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-task-tracker/config.json")

        guard FileManager.default.fileExists(atPath: configPath.path),
              let data = try? Data(contentsOf: configPath),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let langCode = config["language"] as? String,
              let language = Language(rawValue: langCode) else {
            // Default to English
            currentLanguage = .english
            log("Localization: Using default language: english")
            return
        }

        currentLanguage = language
        log("Localization: Loaded language preference: \(language.rawValue)")
    }

    /// Save language preference to config.json
    func setLanguage(_ language: Language) {
        guard language != currentLanguage else { return }

        currentLanguage = language

        // Save to config.json
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-task-tracker/config.json")

        do {
            let dir = configPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var config: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: configPath.path),
               let data = try? Data(contentsOf: configPath),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                config = existing
            }

            config["language"] = language.rawValue

            let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try data.write(to: configPath)

            log("Localization: Saved language preference: \(language.rawValue)")
        } catch {
            log("Localization: Failed to save language: \(error)")
        }

        // Notify observers
        NotificationCenter.default.post(name: Self.languageChangedNotification, object: nil)
    }

    // MARK: - String Lookup

    /// Get localized string for key
    func string(_ key: StringKey) -> String {
        return Strings.get(key, language: currentLanguage)
    }

    /// Convenience subscript
    subscript(key: StringKey) -> String {
        return string(key)
    }
}

// MARK: - Global Shorthand

/// Global function for easy string access: L(.settings_title)
func L(_ key: StringKey) -> String {
    return LocalizationManager.shared.string(key)
}

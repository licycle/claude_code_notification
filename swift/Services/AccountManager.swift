import Foundation

/// Manages Claude Code accounts for task decomposition
/// Loads accounts from ~/.claude-hooks/accounts.json
class AccountManager {
    static let shared = AccountManager()

    private var cachedAccounts: [Account]?
    private var lastFetchTime: Date?
    private let cacheDuration: TimeInterval = 60  // Cache for 60 seconds

    private let accountsPath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-hooks")
        .appendingPathComponent("accounts.json")

    private init() {}

    // MARK: - Public Methods

    /// List available account aliases
    /// - Returns: Array of account aliases, empty if none found
    func listAccounts() -> [String] {
        fetchAccountsIfNeeded()
        return cachedAccounts?.map { $0.alias } ?? []
    }

    /// Get detailed account info
    /// - Returns: Array of Account objects
    func getAccounts() -> [Account] {
        fetchAccountsIfNeeded()
        return cachedAccounts ?? []
    }

    /// Get config directory for a specific alias
    /// - Parameter alias: The account alias (e.g., "c1", "c2")
    /// - Returns: The config directory path, or nil if not found
    func getConfigDir(for alias: String) -> String? {
        fetchAccountsIfNeeded()
        return cachedAccounts?.first { $0.alias == alias }?.configDir
    }

    /// Refresh the account cache
    func refresh() {
        cachedAccounts = nil
        lastFetchTime = nil
        fetchAccountsIfNeeded()
    }

    // MARK: - Private Methods

    private func fetchAccountsIfNeeded() {
        // Check cache validity
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheDuration,
           cachedAccounts != nil {
            return
        }

        // Read directly from JSON file
        cachedAccounts = fetchAccountsFromJSON()
        lastFetchTime = Date()
    }

    private func fetchAccountsFromJSON() -> [Account] {
        guard FileManager.default.fileExists(atPath: accountsPath.path) else {
            log("Accounts file not found: \(accountsPath.path)")
            return []
        }

        do {
            let data = try Data(contentsOf: accountsPath)
            guard let accounts = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
                log("Invalid accounts JSON format")
                return []
            }

            return accounts.map { alias, configDir in
                Account(alias: alias, configDir: configDir)
            }.sorted { $0.alias < $1.alias }
        } catch {
            log("Failed to read accounts: \(error)")
            return []
        }
    }
}

// MARK: - Account Model

struct Account {
    let alias: String       // "c1", "c2"
    let configDir: String   // "/Users/xxx/.claude"

    var displayName: String {
        return alias
    }
}

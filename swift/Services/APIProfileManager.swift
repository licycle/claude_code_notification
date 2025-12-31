import Foundation

/// Manages API profiles for task decomposition
/// Loads profiles from ~/.claude-hooks/api_profiles.json
class APIProfileManager {
    static let shared = APIProfileManager()

    private var cachedProfiles: [APIProfile]?
    private var lastFetchTime: Date?
    private let cacheDuration: TimeInterval = 60  // Cache for 60 seconds

    private let profilesPath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-hooks")
        .appendingPathComponent("api_profiles.json")

    private init() {}

    // MARK: - Public Methods

    /// List available API profiles
    /// - Returns: Array of profile names, empty if none found
    func listProfiles() -> [String] {
        fetchProfilesIfNeeded()
        return cachedProfiles?.map { $0.name } ?? []
    }

    /// Get detailed profile info
    /// - Returns: Array of APIProfile objects
    func getProfiles() -> [APIProfile] {
        fetchProfilesIfNeeded()
        return cachedProfiles ?? []
    }

    /// Refresh the profile cache
    func refresh() {
        cachedProfiles = nil
        lastFetchTime = nil
        fetchProfilesIfNeeded()
    }

    // MARK: - Private Methods

    private func fetchProfilesIfNeeded() {
        // Check cache validity
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheDuration,
           cachedProfiles != nil {
            return
        }

        // Read directly from JSON file
        cachedProfiles = fetchProfilesFromJSON()
        lastFetchTime = Date()
    }

    private func fetchProfilesFromJSON() -> [APIProfile] {
        guard FileManager.default.fileExists(atPath: profilesPath.path) else {
            log("API profiles file not found: \(profilesPath.path)")
            return []
        }

        do {
            let data = try Data(contentsOf: profilesPath)
            guard let profiles = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                log("Invalid API profiles JSON format")
                return []
            }

            return profiles.map { name, config in
                APIProfile(
                    name: name,
                    model: config["ANTHROPIC_MODEL"] as? String ?? config["OPENAI_MODEL"] as? String,
                    baseUrl: config["ANTHROPIC_BASE_URL"] as? String ?? config["OPENAI_API_BASE"] as? String
                )
            }.sorted { $0.name < $1.name }
        } catch {
            log("Failed to read API profiles: \(error)")
            return []
        }
    }
}

// MARK: - API Profile Model

struct APIProfile {
    let name: String
    let model: String?
    let baseUrl: String?

    var displayName: String {
        if let model = model {
            return "\(name) (\(model))"
        }
        return name
    }
}

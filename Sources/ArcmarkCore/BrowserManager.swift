import AppKit

struct BrowserInfo: Equatable {
    let bundleId: String
    let name: String
    let icon: NSImage?
}

struct BrowserProfile {
    let id: String          // Internal identifier ("Profile 1" for Chrome, profile name for Firefox)
    let displayName: String // Human-readable name
}

enum BrowserManager {
    static func installedBrowsers() -> [BrowserInfo] {
        guard let probeURL = URL(string: "http://example.com") else { return [] }
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
        var seen: Set<String> = []
        return urls.compactMap { url in
            guard let bundle = Bundle(url: url) else { return nil }
            guard let bundleId = bundle.bundleIdentifier else { return nil }
            if seen.contains(bundleId) { return nil }
            seen.insert(bundleId)
            let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? bundleId
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return BrowserInfo(bundleId: bundleId, name: name, icon: icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultBrowserBundleId() -> String? {
        guard let probeURL = URL(string: "http://example.com") else { return nil }
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else { return nil }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    static func resolveDefaultBrowserBundleId() -> String? {
        if let stored = UserDefaults.standard.string(forKey: UserDefaultsKeys.defaultBrowserBundleId) {
            return stored
        }
        return defaultBrowserBundleId()
    }

    static func open(url: URL, profile: String? = nil) {
        guard let bundleId = resolveDefaultBrowserBundleId(),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            NSWorkspace.shared.open(url)
            return
        }

        // No profile: use existing NSWorkspace approach
        guard let profile = profile, !profile.isEmpty else {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: nil)
            return
        }

        // With profile: execute browser binary directly (works even when browser is already running)
        guard let bundle = Bundle(url: appURL),
              let executablePath = bundle.executablePath else {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: nil)
            return
        }

        let args = profileArguments(for: bundleId, profile: profile)
        guard !args.isEmpty else {
            // Browser doesn't support profiles, open normally
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: nil)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args + [url.absoluteString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    static func isRunning(bundleId: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }

    static func frontmostApp() -> NSRunningApplication? {
        return NSWorkspace.shared.frontmostApplication
    }

    // MARK: - Browser Profile Support

    static func supportsProfiles(bundleId: String) -> Bool {
        let supported = [
            "com.google.chrome",
            "com.google.chrome.canary",
            "org.mozilla.firefox",
            "org.mozilla.firefoxdeveloperedition"
        ]
        return supported.contains(bundleId.lowercased())
    }

    static func detectProfiles() -> [BrowserProfile] {
        guard let bundleId = resolveDefaultBrowserBundleId() else { return [] }
        let lowered = bundleId.lowercased()

        switch lowered {
        case "com.google.chrome":
            return detectChromeProfiles(supportDir: "Google/Chrome")
        case "com.google.chrome.canary":
            return detectChromeProfiles(supportDir: "Google/Chrome Canary")
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition":
            return detectFirefoxProfiles(supportDir: "Firefox")
        default:
            return []
        }
    }

    static func profileArguments(for bundleId: String, profile: String) -> [String] {
        let lowered = bundleId.lowercased()
        switch lowered {
        case "com.google.chrome", "com.google.chrome.canary":
            return ["--profile-directory=\(profile)"]
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition":
            return ["-P", profile]
        default:
            return []
        }
    }

    // MARK: - Private Profile Detection

    private static func detectChromeProfiles(supportDir: String) -> [BrowserProfile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localStatePath = home
            .appendingPathComponent("Library/Application Support/\(supportDir)/Local State")

        guard let data = try? Data(contentsOf: localStatePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileSection = json["profile"] as? [String: Any],
              let infoCache = profileSection["info_cache"] as? [String: Any] else {
            return []
        }

        var profiles: [BrowserProfile] = []
        for (dirName, value) in infoCache {
            if let profileInfo = value as? [String: Any],
               let name = profileInfo["name"] as? String {
                profiles.append(BrowserProfile(id: dirName, displayName: name))
            }
        }

        return profiles.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func detectFirefoxProfiles(supportDir: String) -> [BrowserProfile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let profilesIniPath = home
            .appendingPathComponent("Library/Application Support/\(supportDir)/profiles.ini")

        guard let contents = try? String(contentsOf: profilesIniPath, encoding: .utf8) else {
            return []
        }

        var profiles: [BrowserProfile] = []
        var currentName: String?

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[Profile") || trimmed.hasPrefix("[Install") {
                if let name = currentName {
                    profiles.append(BrowserProfile(id: name, displayName: name))
                }
                currentName = nil
            }
            if trimmed.lowercased().hasPrefix("name=") {
                let value = String(trimmed.dropFirst(5))
                currentName = value
            }
        }

        // Don't forget the last profile section
        if let name = currentName {
            profiles.append(BrowserProfile(id: name, displayName: name))
        }

        return profiles.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

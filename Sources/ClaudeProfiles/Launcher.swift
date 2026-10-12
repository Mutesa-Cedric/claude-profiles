import AppKit
import ClaudeProfilesCore

enum LauncherError: LocalizedError {
    case claudeNotInstalled

    var errorDescription: String? {
        "Claude for Mac isn't installed. Download it from claude.ai/download, then try again."
    }
}

/// Finds Claude.app and starts, focuses or quits instances of it.
class Launcher {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"
    static let downloadURL = URL(string: "https://claude.ai/download")!

    let profileApps: ProfileApps

    init(profileApps: ProfileApps = ProfileApps()) {
        self.profileApps = profileApps
    }

    /// The real Claude.app. Per-profile copies share its bundle identifier, so they're skipped.
    var appURL: URL? {
        let copies = profileApps.directory.standardizedFileURL.path
        let candidates = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: Self.bundleIdentifier)
            .filter { !$0.standardizedFileURL.path.hasPrefix(copies + "/") }
        if let preferred = candidates.first(where: { $0.path == "/Applications/Claude.app" }) ?? candidates.first {
            return preferred
        }
        let fallback = URL(fileURLWithPath: "/Applications/Claude.app")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    var isClaudeInstalled: Bool { appURL != nil }

    private var executablePath: String? {
        guard let appURL, let executable = Bundle(url: appURL)?.executableURL else { return nil }
        return executable.standardizedFileURL.path
    }

    /// Main process of each running instance, keyed by the profile it belongs to.
    func runningInstances(for profiles: [Profile]) -> [Profile.ID: pid_t] {
        guard let executablePath else { return [:] }
        let idByPath = Dictionary(
            profiles.map { ($0.dataDirectory?.path ?? "", $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        var running: [Profile.ID: pid_t] = [:]
        for process in ProcessScanner.scan(executablePath: executablePath) {
            if let id = idByPath[process.dataDirectory?.path ?? ""] {
                running[id] = process.pid
            }
        }
        return running
    }

    /// Brings the profile's window forward if it's already open, otherwise launches it.
    func open(_ profile: Profile, running: [Profile.ID: pid_t], completion: @escaping (Error?) -> Void) {
        if let pid = running[profile.id], let app = NSRunningApplication(processIdentifier: pid) {
            // Hand our activation over to Claude; the user just clicked us, so this is allowed.
            app.activate(from: .current, options: [.activateAllWindows])
            completion(nil)
            return
        }
        guard let claudeApp = appURL else {
            completion(LauncherError.claudeNotInstalled)
            return
        }

        let launch = { (app: URL) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            // Electron keeps one process per data folder, so a profile always needs its own
            // instance. The stock folder only needs a new one when another instance already
            // owns the app; otherwise a plain open would just focus whatever is running.
            configuration.createsNewApplicationInstance = profile.dataDirectory != nil || !running.isEmpty
            if let directory = profile.dataDirectory {
                configuration.arguments = ["--user-data-dir=\(directory.path)"]
            }
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
                DispatchQueue.main.async { completion(error) }
            }
        }

        guard profile.hasOwnDockIcon, profile.dataDirectory != nil else {
            launch(claudeApp)
            return
        }
        // Cloning takes about a second the first time; keep the menu responsive.
        DispatchQueue.global(qos: .userInitiated).async { [profileApps] in
            do {
                let app = try profileApps.app(for: profile, claudeApp: claudeApp)
                DispatchQueue.main.async { launch(app) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }
}

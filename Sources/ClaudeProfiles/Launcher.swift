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

    var appURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) {
            return url
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
            app.activate(options: [.activateAllWindows])
            completion(nil)
            return
        }
        guard let appURL else {
            completion(LauncherError.claudeNotInstalled)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Electron keeps one process per data folder, so a profile always needs its own
        // instance. The stock folder only needs a new one when another instance already
        // owns the app; otherwise a plain open would just focus whatever is running.
        configuration.createsNewApplicationInstance = profile.dataDirectory != nil || !running.isEmpty
        if let directory = profile.dataDirectory {
            configuration.arguments = ["--user-data-dir=\(directory.path)"]
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }
}

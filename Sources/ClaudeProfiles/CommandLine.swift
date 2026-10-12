import AppKit
import ClaudeProfilesCore

/// Headless commands for scripts and launchers (Raycast, Alfred, shell aliases):
///
///     ClaudeProfiles --list          print every profile and whether it's running
///     ClaudeProfiles --open <name>   open or focus a profile, then exit
enum CommandLineMode {
    static func run(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        switch first {
        case "--list":
            list()
            exit(0)
        case "--open":
            guard arguments.count >= 2 else {
                fail("usage: ClaudeProfiles --open <profile name>")
            }
            open(named: arguments[1...].joined(separator: " "))
            return true
        case "--help", "-h":
            print("""
            Claude Profiles — run several Claude accounts side by side.

              (no arguments)   start the menu bar app
              --list           print profiles and their state
              --open <name>    open or focus a profile by name
            """)
            exit(0)
        default:
            return false
        }
    }

    private static func list() {
        let store = ProfileStore()
        let profiles = store.profiles()
        let running = Launcher().runningInstances(for: profiles)
        for profile in profiles {
            let state = running[profile.id].map { "running (pid \($0))" } ?? "stopped"
            let folder = profile.dataDirectory?.lastPathComponent ?? "(Claude's own folder)"
            print("\(profile.name)\t\(state)\t\(folder)")
        }
    }

    /// Returns once the launch request has been handed to the system.
    private static func open(named name: String) {
        let store = ProfileStore()
        let launcher = Launcher()
        let profiles = store.profiles()
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let profile = profiles.first(where: {
            $0.name.lowercased() == needle || $0.id.lowercased() == needle
        }) else {
            fail("no profile named “\(name)”. Known: \(profiles.map(\.name).joined(separator: ", "))")
        }
        launcher.open(profile, running: launcher.runningInstances(for: profiles)) { error in
            if let error {
                fail(error.localizedDescription)
            }
            exit(0)
        }
        // Keep the process alive until the completion handler exits it.
        RunLoop.main.run()
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}

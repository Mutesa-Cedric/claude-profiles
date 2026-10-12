import AppKit
import Combine
import ClaudeProfilesCore

/// Single source of truth for the menu and the windows: the profile list plus which ones
/// are running. Everything that mutates goes through here so every view refreshes together.
@MainActor
final class ProfilesModel: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var running: [Profile.ID: pid_t] = [:]
    @Published var lastError: String?

    let store: ProfileStore
    let launcher: Launcher
    private var pollTimer: Timer?

    init(store: ProfileStore, launcher: Launcher) {
        self.store = store
        self.launcher = launcher
        refresh()
    }

    var isClaudeInstalled: Bool { launcher.isClaudeInstalled }

    func isRunning(_ profile: Profile) -> Bool { running[profile.id] != nil }

    func refresh() {
        profiles = store.profiles()
        running = launcher.runningInstances(for: profiles)
    }

    /// Launching takes a moment to show up in the process table; check again shortly.
    private func refreshSoon() {
        for delay in [0.8, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
        }
    }

    // MARK: Polling while a window is visible

    func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: Actions

    func open(_ profile: Profile) {
        launcher.open(profile, running: running) { [weak self] error in
            if let error { self?.present(error) }
            self?.refreshSoon()
        }
    }

    func quit(_ profile: Profile) {
        guard let pid = running[profile.id] else { return }
        launcher.quit(pid: pid)
        refreshSoon()
    }

    @discardableResult
    func create(name: String, color: ProfileColor) -> Profile? {
        do {
            let profile = try store.createProfile(named: name, color: color)
            refresh()
            return profile
        } catch {
            present(error)
            return nil
        }
    }

    func update(_ profile: Profile, name: String, color: ProfileColor) {
        do {
            if name != profile.name { try store.rename(profile, to: name) }
            if color != profile.color { try store.setColor(color, for: profile) }
            refresh()
        } catch {
            present(error)
        }
    }

    func setColor(_ color: ProfileColor, for profile: Profile) {
        update(profile, name: profile.name, color: color)
    }

    func trash(_ profile: Profile) {
        do {
            try store.trash(profile)
            refresh()
        } catch {
            present(error)
        }
    }

    func reveal(_ profile: Profile) {
        guard let directory = profile.dataDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private func present(_ error: Error) {
        lastError = error.localizedDescription
    }
}

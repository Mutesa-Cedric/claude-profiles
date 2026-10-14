import AppKit
import ServiceManagement
import ClaudeProfilesCore

/// Builds the status bar menu. It's rebuilt every time it opens so the running state is current.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let model: ProfilesModel
    private let windows: WindowManager

    init(model: ProfilesModel, windows: WindowManager) {
        self.model = model
        self.windows = windows
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuild() }
    }

    func rebuild() {
        model.refresh()
        menu.removeAllItems()

        if !model.isClaudeInstalled {
            let missing = item("Claude for Mac isn't installed", action: nil)
            missing.isEnabled = false
            menu.addItem(missing)
            menu.addItem(item("Download Claude…", action: #selector(downloadClaude)))
            menu.addItem(.separator())
        }

        if !model.pausedForSignIn.isEmpty {
            let names = model.pausedForSignIn.map(\.name).formatted(.list(type: .and))
            let reopen = item("Reopen \(names)", action: #selector(reopenPaused), key: "r")
            reopen.toolTip = "These were quit so another profile could sign in."
            menu.addItem(reopen)
            menu.addItem(.separator())
        }

        for (index, profile) in model.profiles.enumerated() {
            let running = model.isRunning(profile)
            let entry = item(profile.name, action: #selector(openProfile(_:)), key: index < 9 ? String(index + 1) : "")
            entry.image = ProfileBadge.image(for: profile)
            entry.representedObject = profile
            entry.state = running ? .on : .off
            entry.toolTip = running ? "Open — click to bring its window forward" : "Click to open"
            entry.isEnabled = model.isClaudeInstalled
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(item("New Profile…", action: #selector(newProfile), key: "n"))
        menu.addItem(item("Manage Profiles…", action: #selector(manageProfiles), key: ","))
        menu.addItem(.separator())

        let login = item("Launch at Login", action: #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if !Self.isBundled {
            login.isEnabled = false
            login.toolTip = "Available once the app is installed in Applications."
        }
        menu.addItem(login)
        menu.addItem(item("About Claude Profiles", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private func item(_ title: String, action: Selector?, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    // MARK: Actions

    @objc private func openProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? Profile else { return }
        model.open(profile)
    }

    @objc private func newProfile() { windows.showEditor(.create) }

    @objc private func reopenPaused() { model.reopenPaused() }

    @objc private func manageProfiles() { windows.showManage() }

    @objc private func downloadClaude() { NSWorkspace.shared.open(Launcher.downloadURL) }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func showAbout() {
        NSApp.activate()
        let credits = NSMutableAttributedString(
            string: "Run several Claude accounts side by side.\n",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.secondaryLabelColor])
        credits.append(NSAttributedString(
            string: "github.com/Mutesa-Cedric/claude-profiles",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .link: URL(string: "https://github.com/Mutesa-Cedric/claude-profiles")!]))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

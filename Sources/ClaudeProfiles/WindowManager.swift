import AppKit
import SwiftUI
import ClaudeProfilesCore

/// Owns the app's two windows. A menu bar app has no main window, so these are created on
/// demand and brought forward together with the app.
@MainActor
final class WindowManager {
    let model: ProfilesModel
    private(set) var manageWindow: NSWindow?
    private(set) var editorWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(model: ProfilesModel) {
        self.model = model
    }

    func showManage() {
        if manageWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: ManageProfilesView(model: model, windows: self)))
            window.title = "Claude Profiles"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 360))
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("ManageProfiles")
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.model.stopPolling() }
            })
            manageWindow = window
        }
        model.refresh()
        model.startPolling()
        present(manageWindow!)
    }

    func showEditor(_ mode: ProfileEditorView.Mode, initialName: String? = nil) {
        editorWindow?.close()

        let view = ProfileEditorView(
            mode: mode,
            initialName: initialName,
            onSave: { [weak self] result in
                guard let self else { return }
                switch mode {
                case .create:
                    if let profile = self.model.create(
                        name: result.name, color: result.color, ownDockIcon: result.ownDockIcon) {
                        self.closeEditor()
                        // A new profile's first act is signing in, which needs the guard below.
                        self.confirmSignIn(for: profile)
                    }
                case .edit(let profile):
                    self.model.update(
                        profile, name: result.name, color: result.color, ownDockIcon: result.ownDockIcon)
                    self.closeEditor()
                }
            },
            onCancel: { [weak self] in self?.closeEditor() }
        )

        let hosting = NSHostingController(rootView: view)
        hosting.view.frame.size = hosting.view.fittingSize
        let window = NSWindow(contentViewController: hosting)
        if case .edit(let profile) = mode {
            window.title = "Edit “\(profile.name)”"
        } else {
            window.title = "New Profile"
        }
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        // Sit over the manage window when it's open, otherwise just come to the front.
        if let manageWindow, manageWindow.isVisible {
            let frame = manageWindow.frame
            window.setFrameOrigin(NSPoint(
                x: frame.midX - window.frame.width / 2,
                y: frame.midY - window.frame.height / 2))
        }
        editorWindow = window
        present(window)
    }

    private func closeEditor() {
        editorWindow?.close()
        editorWindow = nil
    }

    enum SignInChoice {
        case quitOthers, openAnyway, cancel
    }

    /// Replaces the sign-in alert; the self-test uses it so no real window gets quit.
    var signInPrompt: ((Profile, [Profile]) -> SignInChoice)?

    /// Opens a profile to sign in. When other profiles are open, offers to quit them first so
    /// the browser's sign-in link can only come back to this one (see `ProfilesModel.signIn`).
    func confirmSignIn(for profile: Profile) {
        model.refresh()
        let others = model.otherRunningProfiles(than: profile)
        guard !others.isEmpty else {
            model.open(profile)
            return
        }
        switch signInPrompt?(profile, others) ?? askAboutSignIn(for: profile, others: others) {
        case .quitOthers:
            model.signIn(profile, quittingOthers: true)
        case .openAnyway:
            model.open(profile)
        case .cancel:
            break
        }
    }

    private func askAboutSignIn(for profile: Profile, others: [Profile]) -> SignInChoice {
        let names = others.map { "“\($0.name)”" }.formatted(.list(type: .and))
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Quit \(names) while you sign in to “\(profile.name)”?"
        alert.informativeText = "Claude signs in through your browser and comes back through a link that macOS hands to whichever Claude window it picks. With other profiles open, the login can land in the wrong one. Quitting them for a moment makes sure it reaches “\(profile.name)”; you can reopen them from the menu afterwards."
        alert.addButton(withTitle: "Quit Others & Open")
        alert.addButton(withTitle: "Open Anyway")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .quitOthers
        case .alertSecondButtonReturn: return .openAnyway
        default: return .cancel
        }
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

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
            onSave: { [weak self] name, color in
                guard let self else { return }
                switch mode {
                case .create:
                    if let profile = self.model.create(name: name, color: color) {
                        self.closeEditor()
                        self.model.open(profile)
                    }
                case .edit(let profile):
                    self.model.update(profile, name: name, color: color)
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

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

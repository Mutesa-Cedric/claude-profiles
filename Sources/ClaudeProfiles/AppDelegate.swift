import AppKit
import ClaudeProfilesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model: ProfilesModel
    private let windows: WindowManager
    private let menuController: MenuController
    private var statusItem: NSStatusItem?

    init(model: ProfilesModel) {
        self.model = model
        self.windows = WindowManager(model: model)
        self.menuController = MenuController(model: model, windows: windows)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let symbol = NSImage(systemSymbolName: "person.crop.rectangle.stack", accessibilityDescription: "Claude Profiles")
            button.image = symbol?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
            button.image?.isTemplate = true
            button.toolTip = "Claude Profiles"
        }
        item.menu = menuController.menu
        statusItem = item
    }

    /// Opening the app again (Finder, Spotlight, Dock) while it's running shows the window,
    /// so a menu-bar-only app never looks like it did nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        windows.showManage()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

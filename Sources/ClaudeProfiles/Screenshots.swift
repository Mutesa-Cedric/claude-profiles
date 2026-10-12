import AppKit
import ClaudeProfilesCore

/// `claude-profiles --capture <dir>` renders the real UI with demo data into PNGs for the README.
///
/// Windows are rendered in-process (`cacheDisplay`), which needs no screen-recording
/// permission and never touches the user's own profiles: the demo store lives in a temp folder.
@MainActor
final class ScreenshotDelegate: NSObject, NSApplicationDelegate {
    private let outputDirectory: URL
    private var keep: [AnyObject] = []

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let store = try Self.makeDemoStore()
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                try capture(store: store, suffix: suffix)
            }
            try? FileManager.default.removeItem(at: store.supportDirectory.deletingLastPathComponent())
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("capture failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func makeDemoStore() throws -> ProfileStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-profiles-demo-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let store = ProfileStore(supportDirectory: support, metadataURL: root.appendingPathComponent("profiles.json"))
        try store.createProfile(named: "Work", color: .blue)
        try store.createProfile(named: "Personal", color: .orange)
        try store.createProfile(named: "Freelance", color: .green)
        return store
    }

    private func capture(store: ProfileStore, suffix: String) throws {
        let model = ProfilesModel(store: store, launcher: DemoLauncher())
        let windows = WindowManager(model: model)
        let menuController = MenuController(model: model, windows: windows)
        keep += [model, windows, menuController]

        // Menu
        menuController.rebuild()
        if let image = MenuRenderer.render(menuController.menu, dark: suffix == "dark") {
            try write(image, name: "menu-\(suffix)")
        } else {
            FileHandle.standardError.write(Data("warning: menu could not be rendered\n".utf8))
        }

        // Manage window
        windows.showManage()
        if let window = windows.manageWindow {
            settle()
            try write(WindowRenderer.render(window), name: "manage-\(suffix)")
            window.close()
        }

        // Editor, with a name typed in so the badge preview shows something.
        windows.showEditor(.create, initialName: "Side project")
        if let window = windows.editorWindow {
            settle()
            try write(WindowRenderer.render(window), name: "new-profile-\(suffix)")
            window.close()
        }
    }

    /// Lets SwiftUI lay out and the window become key before it's rendered.
    private func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
    }

    private func write(_ image: NSBitmapImageRep, name: String) throws {
        guard let png = image.representation(using: .png, properties: [:]) else { return }
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("wrote \(url.path)")
    }
}

/// Pretends Claude is installed and that two profiles are open, without launching anything.
@MainActor
private final class DemoLauncher: Launcher {
    override var isClaudeInstalled: Bool { true }

    override func runningInstances(for profiles: [Profile]) -> [Profile.ID: pid_t] {
        var running: [Profile.ID: pid_t] = [:]
        for profile in profiles where profile.isDefault || profile.name == "Work" {
            running[profile.id] = 1
        }
        return running
    }

    override func open(_ profile: Profile, running: [Profile.ID: pid_t], completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
}

enum WindowRenderer {
    /// Renders the whole window including its title bar, with rounded corners like on screen.
    static func render(_ window: NSWindow, cornerRadius: CGFloat = 10) -> NSBitmapImageRep {
        window.layoutIfNeeded()
        window.displayIfNeeded()
        let frameView = window.contentView!.superview!
        let bounds = frameView.bounds
        let source = frameView.bitmapImageRepForCachingDisplay(in: bounds)!
        frameView.cacheDisplay(in: bounds, to: source)
        return rounded(source, radius: cornerRadius)
    }

    static func rounded(
        _ source: NSBitmapImageRep, radius: CGFloat, background: NSColor? = nil, border: NSColor? = nil
    ) -> NSBitmapImageRep {
        let target = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: source.pixelsWide, pixelsHigh: source.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        target.size = source.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        let rect = NSRect(origin: .zero, size: source.size)
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        shape.addClip()
        if let background {
            background.setFill()
            shape.fill()
        }
        // `draw(in:)` alone would copy the transparent pixels over the backdrop.
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if let border {
            border.setStroke()
            let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            inner.lineWidth = 1
            inner.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        return target
    }
}

enum MenuRenderer {
    /// Pops the menu up for real and renders the window AppKit draws it in.
    ///
    /// On screen the menu sits on a blurred material; offscreen that material is transparent,
    /// so the content is composited onto a flat menu-colored backdrop with a hairline border.
    static func render(_ menu: NSMenu, dark: Bool) -> NSBitmapImageRep? {
        var result: NSBitmapImageRep?
        // Menu tracking runs its own run loop; a timer in common modes still fires inside it.
        let timer = Timer(timeInterval: 0.4, repeats: false) { _ in
            // AppKit keeps old menu windows around hidden; only the visible one is this menu.
            if let window = NSApp.windows.first(where: {
                $0.isVisible && NSStringFromClass(type(of: $0)).contains("Menu")
            }), let view = window.contentView {
                window.displayIfNeeded()
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    result = WindowRenderer.rounded(
                        rep, radius: 6,
                        background: dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.97, alpha: 1),
                        border: dark ? NSColor(white: 1, alpha: 0.15) : NSColor(white: 0, alpha: 0.12))
                }
            }
            menu.cancelTracking()
        }
        RunLoop.main.add(timer, forMode: .common)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        menu.popUp(positioning: nil, at: NSPoint(x: screen.midX, y: screen.midY), in: nil)
        return result
    }
}

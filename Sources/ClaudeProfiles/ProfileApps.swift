import AppKit
import ClaudeProfilesCore

enum ProfileAppsError: LocalizedError {
    case copyFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let status):
            return "Couldn't make a copy of Claude for this profile (cp exited with \(status))."
        }
    }
}

/// Per-profile copies of Claude.app, so a profile can have its own Dock icon.
///
/// macOS shows the icon of the bundle a process was launched from, and every profile
/// normally runs from the same Claude.app. A copy fixes that. It's an APFS clone, so it's
/// instant and takes no space until Claude updates; then it's rebuilt on the next launch.
///
/// The copy's contents are never modified: Gatekeeper re-checks a copied app's code
/// signature on first launch (the copy inherits Claude's download provenance) and rejects
/// any change inside it as "damaged". A Finder custom icon lives outside the sealed
/// contents, which is why that's the one thing a copy gets — and why the Dock name
/// stays "Claude".
final class ProfileApps {

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Claude Profiles", isDirectory: true)
    }

    let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL = ProfileApps.defaultDirectory) {
        self.directory = directory
    }

    func url(for profile: Profile) -> URL {
        let safe = "Claude · \(profile.name)"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("\(safe).app", isDirectory: true)
    }

    func exists(for profile: Profile) -> Bool {
        fileManager.fileExists(atPath: url(for: profile).path)
    }

    func isRunning(_ app: URL) -> Bool {
        let path = app.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL.path == path }
    }

    /// Returns a ready-to-launch copy, building it or refreshing a stale one as needed.
    func app(for profile: Profile, claudeApp: URL) throws -> URL {
        let app = url(for: profile)
        if fileManager.fileExists(atPath: app.path) {
            if isRunning(app) || version(of: app) == version(of: claudeApp) {
                try applyIcon(for: profile, to: app, claudeApp: claudeApp)
                return app
            }
            try fileManager.removeItem(at: app)
        }
        try build(for: profile, from: claudeApp, at: app)
        return app
    }

    /// Deletes the profile's copy unless it's in use.
    func remove(for profile: Profile) throws {
        let app = url(for: profile)
        guard fileManager.fileExists(atPath: app.path), !isRunning(app) else { return }
        try fileManager.removeItem(at: app)
    }

    /// Deletes copies that no longer belong to a profile with the option on (renamed,
    /// deleted, or switched off). Only Claude copies inside our own folder are touched.
    func removeOrphans(keeping profiles: [Profile]) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let wanted = Set(profiles.filter(\.hasOwnDockIcon).map { url(for: $0).standardizedFileURL.path })
        for entry in entries where entry.pathExtension == "app" {
            guard !wanted.contains(entry.standardizedFileURL.path),
                  bundleIdentifier(of: entry) == Launcher.bundleIdentifier,
                  !isRunning(entry)
            else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }

    // MARK: Building

    private func build(for profile: Profile, from claudeApp: URL, at app: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // `cp -c` clones on APFS: instant, and shares storage with the original.
        let cp = Process()
        cp.executableURL = URL(fileURLWithPath: "/bin/cp")
        cp.arguments = ["-Rc", claudeApp.path, app.path]
        cp.standardOutput = FileHandle.nullDevice
        cp.standardError = FileHandle.nullDevice
        try cp.run()
        cp.waitUntilExit()
        guard cp.terminationStatus == 0 else { throw ProfileAppsError.copyFailed(cp.terminationStatus) }

        try applyIcon(for: profile, to: app, claudeApp: claudeApp)
    }

    private func applyIcon(for profile: Profile, to app: URL, claudeApp: URL) throws {
        let base = NSWorkspace.shared.icon(forFile: claudeApp.path)
        let composed = DockIconComposer.compose(base: base, profile: profile)
        NSWorkspace.shared.setIcon(composed, forFile: app.path, options: [])
    }

    private func version(of app: URL) -> String? {
        info(of: app)?["CFBundleVersion"] as? String
    }

    private func bundleIdentifier(of app: URL) -> String? {
        info(of: app)?["CFBundleIdentifier"] as? String
    }

    private func info(of app: URL) -> NSDictionary? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    }
}

/// Claude's icon with the profile's colored initial in the corner.
enum DockIconComposer {
    static func compose(base: NSImage, profile: Profile, size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

            // Claude's artwork sits inside the standard ~10% transparent margin; the badge
            // overlaps the tile's bottom-right corner the way Dock badges do.
            let diameter = size * 0.40
            let badge = NSRect(x: size * 0.86 - diameter, y: size * 0.12, width: diameter, height: diameter)
            let ring = badge.insetBy(dx: -size * 0.025, dy: -size * 0.025)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = size * 0.02
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: ring).fill()
            NSGraphicsContext.restoreGraphicsState()

            profile.color.nsColor.setFill()
            NSBezierPath(ovalIn: badge).fill()

            let font = NSFont.systemFont(ofSize: diameter * 0.58, weight: .bold)
            let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) }
            let text = NSAttributedString(string: profile.initial, attributes: [
                .font: rounded ?? font,
                .foregroundColor: NSColor.white,
            ])
            let textSize = text.size()
            text.draw(at: NSPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2))
            return true
        }
        return image
    }
}

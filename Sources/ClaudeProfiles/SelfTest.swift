import AppKit
import ServiceManagement
import ClaudeProfilesCore

/// `ClaudeProfiles --self-test <dir>` exercises the real app against a real Claude install:
///
/// 1. presses "Create & Open" in the New Profile window → a Claude instance launches
/// 2. checks the Manage window shows it running and presses "Show"
/// 3. runs the menu item's action for a running profile (must focus, not relaunch)
/// 4. renames through the editor's "Save", recolors, quits Claude, trashes the profile
/// 5. registers and unregisters Launch at Login, restoring the original state
///
/// Buttons are pressed through the app's own accessibility tree, so this needs no
/// Accessibility or Screen Recording permission. Everything happens in a temp folder; the
/// user's real profiles are never touched. Screenshots of each state are written to `<dir>`
/// as evidence. Run it from the installed bundle so Launch at Login can be tested.
@MainActor
final class SelfTestDelegate: NSObject, NSApplicationDelegate {
    private let outputDirectory: URL
    private var failures: [String] = []
    private var passes = 0
    /// Set once a profile has been launched so an aborted run can still quit it.
    private var launched: (model: ProfilesModel, profile: Profile)?

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI only builds its accessibility nodes once an assistive client announces
        // itself; this is the same flag VoiceOver sets, applied to our own process.
        _ = NSApp.perform(
            NSSelectorFromString("accessibilitySetValue:forAttribute:"),
            with: NSNumber(value: true), with: "AXEnhancedUserInterface")

        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                try await run()
            } catch {
                fail("aborted: \(error.localizedDescription)")
                await quitStrayInstance()
            }
            print("\n\(passes) passed, \(failures.count) failed")
            exit(failures.isEmpty ? 0 : 1)
        }
    }

    // MARK: Scenario

    private func run() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-profiles-selftest-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Copies go in a sub-folder of the real location so they behave like the real thing,
        // while orphan cleanup (which only scans its own folder) can't touch real copies.
        let copies = ProfileApps.defaultDirectory.appendingPathComponent("Self Test", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: copies) }
        let launcher = Launcher(profileApps: ProfileApps(directory: copies))
        guard launcher.isClaudeInstalled else { throw SelfTestError("Claude for Mac is not installed") }

        let store = ProfileStore(supportDirectory: support, metadataURL: root.appendingPathComponent("profiles.json"))
        let model = ProfilesModel(store: store, launcher: launcher)
        let windows = WindowManager(model: model)
        let menuController = MenuController(model: model, windows: windows)

        // The sign-in guard would show a modal alert whenever another Claude window is open
        // (the user's Default usually is). Answer it here, choosing to open without quitting
        // anything, and remember what it was asked about.
        var guardAskedAbout: [Profile]?
        windows.signInPrompt = { _, others in
            guardAskedAbout = others
            return .openAnyway
        }

        // 1. New Profile window → Create & Open
        windows.showEditor(.create, initialName: "Self Test")
        await settle()
        let editor = try require(windows.editorWindow, "editor window is shown")
        try capture(editor, "1-new-profile")
        check("editor shows the typed name", texts(in: editor, role: "AXTextField").contains("Self Test"))
        try press("Create & Open", in: editor)
        await settle()
        check("editor closes after Create & Open", windows.editorWindow == nil)

        let created = try require(model.profiles.first { $0.name == "Self Test" }, "profile appears in the model")
        if let defaultProfile = model.profiles.first, model.isRunning(defaultProfile) {
            check("Create & Open consults the sign-in guard about the open Default",
                  guardAskedAbout?.map(\.id) == [Profile.defaultID])
        } else {
            check("Create & Open skips the sign-in guard when nothing else is open", guardAskedAbout == nil)
        }
        check("profile folder was created", FileManager.default.fileExists(atPath: created.dataDirectory!.path))
        launched = (model, created)
        try await waitUntil("Claude launches for the new profile", timeout: 30) {
            model.refresh()
            return model.isRunning(created)
        }

        // 2. Manage window shows it running; Show focuses it
        windows.showManage()
        await settle(1)
        let manage = try require(windows.manageWindow, "manage window is shown")
        try capture(manage, "2-manage-running")
        check("manage window shows the profile", texts(in: manage).contains("Self Test"))
        check("manage window marks it Running", texts(in: manage).contains("Running"))
        try press("Show", in: manage, after: "Self Test")
        await settle(1.5)
        // Only an active app may hand activation to another one; a process started from a
        // shell may never have been made active, in which case the hand-over is a no-op.
        if NSApp.isActive {
            check("Claude is frontmost after Show",
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Launcher.bundleIdentifier)
        } else {
            print("skip: Claude is frontmost after Show (this process isn't active)")
        }

        // 3. Menu item for a running profile focuses instead of relaunching
        menuController.rebuild()
        let menu = menuController.menu
        let index = try require(menu.items.firstIndex { ($0.representedObject as? Profile)?.id == created.id },
                                "menu lists the profile")
        check("menu item is checked while running", menu.items[index].state == .on)
        check("menu item has a ⌘ shortcut", !menu.items[index].keyEquivalent.isEmpty)
        menu.performActionForItem(at: index)
        await settle(2)
        model.refresh()
        check("still exactly one instance after menu action", instanceCount(for: created) == 1)
        let newItem = try require(menu.items.first { $0.title == "New Profile…" }, "menu has New Profile…")
        menu.performActionForItem(at: menu.index(of: newItem))
        await settle()
        check("New Profile… opens the editor", windows.editorWindow?.title == "New Profile")
        if let window = windows.editorWindow {
            try press("Cancel", in: window)
            await settle()
            check("Cancel closes the editor", windows.editorWindow == nil)
        }

        // 4. Rename through the editor, recolor, quit, trash
        windows.showEditor(.edit(created), initialName: "Self Test Renamed")
        await settle()
        let renameEditor = try require(windows.editorWindow, "edit window is shown")
        check("edit window title names the profile", renameEditor.title.contains("Self Test"))
        try press("Save", in: renameEditor)
        await settle()
        check("rename is stored", store.profiles().first { $0.id == created.id }?.name == "Self Test Renamed")
        check("rename keeps the folder", FileManager.default.fileExists(atPath: created.dataDirectory!.path))
        check("manage window shows the new name", texts(in: manage).contains("Self Test Renamed"))

        model.setColor(.pink, for: created)
        check("color is stored", store.profiles().first { $0.id == created.id }?.color == .pink)
        await settle(1)
        try capture(manage, "3-manage-renamed")

        model.quit(created)
        try await waitUntil("Claude quits for the profile", timeout: 30) {
            model.refresh()
            return !model.isRunning(created)
        }
        await settle(1)
        try capture(manage, "4-manage-stopped")
        check("manage window offers Open again", buttons(in: manage, after: "Self Test Renamed").contains("Open"))

        // 5. Separate Dock icon: the profile launches through its own copy of Claude
        model.setOwnDockIcon(true, for: created)
        let docked = try require(model.profiles.first { $0.id == created.id && $0.hasOwnDockIcon },
                                 "Dock icon option is stored")
        model.open(docked)
        try await waitUntil("Claude launches through the profile's copy", timeout: 60) {
            model.refresh()
            return model.isRunning(docked)
        }
        let copy = launcher.profileApps.url(for: docked)
        check("copy exists in the profile apps folder", FileManager.default.fileExists(atPath: copy.path))
        if let pid = model.running[docked.id], let app = NSRunningApplication(processIdentifier: pid) {
            check("instance runs from the copy",
                  app.bundleURL?.standardizedFileURL.path == copy.standardizedFileURL.path)
            let name = app.localizedName ?? ""
            print("info  the copy is listed as “\(name)”")
            check("instance is named Claude or after its file",
                  name == "Claude" || name == copy.deletingPathExtension().lastPathComponent)
            let claudeIcon = NSWorkspace.shared.icon(forFile: launcher.appURL!.path).tiffRepresentation
            check("instance has its own icon", app.icon?.tiffRepresentation != claudeIcon)
        } else {
            fail("running instance not found for the copy")
        }
        await settle(1)
        try capture(manage, "5-manage-dock-icon")
        if let claudeApp = launcher.appURL,
           let png = DockIconComposer
               .compose(base: NSWorkspace.shared.icon(forFile: claudeApp.path), profile: docked, size: 256)
               .tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) })?
               .representation(using: .png, properties: [:]) {
            try png.write(to: outputDirectory.appendingPathComponent("6-dock-icon.png"))
        }
        model.quit(docked)
        try await waitUntil("the copy quits", timeout: 30) {
            model.refresh()
            return !model.isRunning(docked)
        }
        model.setOwnDockIcon(false, for: docked)
        for _ in 0..<10 where FileManager.default.fileExists(atPath: copy.path) {
            await settle(0.5)
            model.refresh()
        }
        check("copy is removed when the option is switched off", !FileManager.default.fileExists(atPath: copy.path))
        manage.close()

        let trashed = try store.trash(created)
        check("trash removes the folder", !FileManager.default.fileExists(atPath: created.dataDirectory!.path))
        check("trash keeps a copy to restore", FileManager.default.fileExists(atPath: trashed.path))
        try? FileManager.default.removeItem(at: trashed)
        model.refresh()
        check("model forgets the profile", !model.profiles.contains { $0.id == created.id })

        // 5. Sign-in guard: quits the other profiles, opens the target once they're gone, and
        //    can bring them back. Uses a recording launcher so nothing real is quit.
        do {
            let recorder = RecordingLauncher(profileApps: launcher.profileApps)
            let signInStore = ProfileStore(
                supportDirectory: root.appendingPathComponent("SignIn/Application Support", isDirectory: true),
                metadataURL: root.appendingPathComponent("SignIn/profiles.json"))
            try FileManager.default.createDirectory(at: signInStore.supportDirectory, withIntermediateDirectories: true)
            let alpha = try signInStore.createProfile(named: "Alpha")
            let beta = try signInStore.createProfile(named: "Beta")
            recorder.runningIDs = [Profile.defaultID, alpha.id]
            let signInModel = ProfilesModel(store: signInStore, launcher: recorder)

            check("sign-in sees the other open profiles",
                  Set(signInModel.otherRunningProfiles(than: beta).map(\.id)) == [Profile.defaultID, alpha.id])
            signInModel.signIn(beta, quittingOthers: true)
            await settle(1.5)
            check("sign-in quits the other profiles", Set(recorder.quitIDs) == [Profile.defaultID, alpha.id])
            check("sign-in opens the target once they're gone", recorder.openedIDs == [beta.id])
            check("quit profiles are remembered for reopening",
                  Set(signInModel.pausedForSignIn.map(\.id)) == [Profile.defaultID, alpha.id])
            signInModel.reopenPaused()
            check("reopen brings them back", Set(recorder.openedIDs.dropFirst()) == [Profile.defaultID, alpha.id])
            check("reopen clears the list", signInModel.pausedForSignIn.isEmpty)

            recorder.openedIDs = []
            signInModel.signIn(alpha, quittingOthers: false)
            await settle(0.3)
            check("Open Anyway just opens", recorder.openedIDs == [alpha.id] && signInModel.pausedForSignIn.isEmpty)
        }

        // 6. Launch at Login round trip (installed bundle only), restored afterwards
        if Bundle.main.bundleURL.pathExtension == "app" {
            let service = SMAppService.mainApp
            let original = service.status
            do {
                if original == .enabled {
                    try await service.unregister()
                    check("Launch at Login can be turned off", service.status != .enabled)
                    try service.register()
                    check("Launch at Login can be turned back on", service.status == .enabled)
                } else {
                    try service.register()
                    check("Launch at Login can be turned on", service.status == .enabled)
                    try await service.unregister()
                    check("Launch at Login can be turned off again", service.status != .enabled)
                }
            } catch {
                fail("Launch at Login: \(error.localizedDescription)")
            }
            // .notFound and .notRegistered both mean "off".
            check("Launch at Login restored to its original state",
                  (service.status == .enabled) == (original == .enabled))
        } else {
            print("skip: Launch at Login (not running from an .app bundle)")
        }
    }

    private func quitStrayInstance() async {
        guard let (model, profile) = launched else { return }
        model.refresh()
        guard model.isRunning(profile) else { return }
        print("cleanup: quitting the Claude instance left over from the aborted run")
        model.quit(profile)
        for _ in 0..<20 {
            await settle(0.5)
            model.refresh()
            if !model.isRunning(profile) { return }
        }
    }

    // MARK: Accessibility driving
    //
    // SwiftUI's nodes implement the accessibility selectors without declaring the protocol,
    // so they are reached dynamically; see `Element`.

    private struct Element {
        let object: NSObject
        var role: String { attribute("accessibilityRole") as? String ?? "" }
        var title: String { attribute("accessibilityTitle") as? String ?? "" }
        var label: String { attribute("accessibilityLabel") as? String ?? "" }
        var value: String { attribute("accessibilityValue") as? String ?? "" }
        var children: [Any] { attribute("accessibilityChildren") as? [Any] ?? [] }

        /// SwiftUI's `AccessibilityNode` implements the accessibility selectors without
        /// declaring `NSAccessibilityProtocol`, so they're reached through KVC.
        private func attribute(_ selector: String) -> Any? {
            guard object.responds(to: NSSelectorFromString(selector)) else { return nil }
            return object.value(forKey: selector)
        }

        @discardableResult
        func press() -> Bool {
            let selector = NSSelectorFromString("accessibilityPerformPress")
            guard object.responds(to: selector),
                  let implementation = class_getMethodImplementation(type(of: object), selector)
            else { return false }
            typealias Press = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(implementation, to: Press.self)(object, selector)
        }
    }

    /// Depth-first list of accessibility elements under a window's content view.
    ///
    /// SwiftUI's `List` is an `NSOutlineView` whose row proxies don't hand out their
    /// children here, so table rows are walked through their real cell views instead.
    private func elements(in window: NSWindow) -> [Element] {
        var found: [Element] = []
        func visit(_ node: Any) {
            guard let object = node as? NSObject else { return }
            let element = Element(object: object)
            found.append(element)
            if let table = object as? NSTableView {
                for row in 0..<table.numberOfRows {
                    for column in 0..<table.numberOfColumns {
                        if let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) {
                            visit(cell)
                        }
                    }
                }
                return
            }
            element.children.forEach(visit)
        }
        if let content = window.contentView { visit(content) }
        return found
    }

    private func texts(in window: NSWindow, role: String = "AXStaticText") -> [String] {
        elements(in: window).filter { $0.role == role }.map(\.value)
    }

    /// Button titles in document order, optionally only those after the static text `anchor`.
    private func buttons(in window: NSWindow, after anchor: String? = nil) -> [String] {
        var armed = anchor == nil
        var titles: [String] = []
        for element in elements(in: window) {
            if !armed {
                if element.role == "AXStaticText", element.value == anchor { armed = true }
                continue
            }
            if element.role == "AXButton" {
                titles.append(element.title.isEmpty ? element.label : element.title)
            }
        }
        return titles
    }

    /// Presses the first button titled `title`, optionally only after the static text `anchor`
    /// has been seen (so "Show" in a given row can be picked).
    private func press(_ title: String, in window: NSWindow, after anchor: String? = nil) throws {
        var armed = anchor == nil
        for element in elements(in: window) {
            if !armed {
                if element.role == "AXStaticText", element.value == anchor { armed = true }
                continue
            }
            guard element.role == "AXButton" else { continue }
            if element.title == title || element.label == title {
                check("press “\(title)”", element.press())
                return
            }
        }
        dump(window)
        throw SelfTestError("no button titled “\(title)” in “\(window.title)”")
    }

    /// Prints the accessibility tree, for diagnosing a press that found nothing.
    private func dump(_ window: NSWindow) {
        for element in elements(in: window) {
            print("  \(NSStringFromClass(type(of: element.object))) role=\(element.role) title=\(element.title) label=\(element.label) value=\(element.value)")
        }
    }

    // MARK: Helpers

    private func instanceCount(for profile: Profile) -> Int {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axww", "-o", "command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try? ps.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        let path = profile.dataDirectory!.path
        return output.split(separator: "\n").filter {
            $0.hasSuffix("/Contents/MacOS/Claude --user-data-dir=\(path)")
        }.count
    }

    private func capture(_ window: NSWindow, _ name: String) throws {
        let image = WindowRenderer.render(window)
        guard let png = image.representation(using: .png, properties: [:]) else { return }
        try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }

    private func settle(_ seconds: Double = 0.6) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func waitUntil(_ what: String, timeout: Double, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { check(what, true); return }
            await settle(0.5)
        }
        check(what, false)
        throw SelfTestError("timed out waiting: \(what)")
    }

    private func require<T>(_ value: T?, _ what: String) throws -> T {
        guard let value else {
            check(what, false)
            throw SelfTestError(what)
        }
        check(what, true)
        return value
    }

    private func check(_ what: String, _ ok: Bool) {
        if ok {
            passes += 1
            print("PASS  \(what)")
        } else {
            fail(what)
        }
    }

    private func fail(_ what: String) {
        failures.append(what)
        print("FAIL  \(what)")
    }
}

/// Stands in for Claude: remembers what was opened and quit instead of touching real windows.
private final class RecordingLauncher: Launcher {
    var runningIDs: Set<Profile.ID> = []
    var openedIDs: [Profile.ID] = []
    var quitIDs: [Profile.ID] = []
    private var pids: [Profile.ID: pid_t] = [:]

    override var isClaudeInstalled: Bool { true }

    override func runningInstances(for profiles: [Profile]) -> [Profile.ID: pid_t] {
        var result: [Profile.ID: pid_t] = [:]
        for profile in profiles where runningIDs.contains(profile.id) {
            let pid = pids[profile.id] ?? pid_t(1000 + pids.count)
            pids[profile.id] = pid
            result[profile.id] = pid
        }
        return result
    }

    override func open(_ profile: Profile, running: [Profile.ID: pid_t], completion: @escaping (Error?) -> Void) {
        openedIDs.append(profile.id)
        runningIDs.insert(profile.id)
        completion(nil)
    }

    override func quit(pid: pid_t) {
        guard let id = pids.first(where: { $0.value == pid })?.key else { return }
        quitIDs.append(id)
        runningIDs.remove(id)
    }
}

private struct SelfTestError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

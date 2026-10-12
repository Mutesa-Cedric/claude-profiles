import AppKit
import ClaudeProfilesCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let arguments = Array(CommandLine.arguments.dropFirst())
MainActor.assumeIsolated {
    if let flag = arguments.firstIndex(of: "--capture"), arguments.indices.contains(flag + 1) {
        // Screenshot mode used by `make screenshots`; see Screenshots.swift.
        let delegate = ScreenshotDelegate(outputDirectory: URL(fileURLWithPath: arguments[flag + 1]))
        app.delegate = delegate
        app.run()
    } else if CommandLineMode.run(arguments) {
        // Handled headlessly; `run` exits when done.
    } else {
        let model = ProfilesModel(store: ProfileStore(), launcher: Launcher())
        let delegate = AppDelegate(model: model)
        app.delegate = delegate
        app.run()
    }
}

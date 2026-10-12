import Foundation

/// A running main Claude process and the profile folder it was started with.
public struct ClaudeProcess: Equatable, Sendable {
    public let pid: pid_t
    /// `nil` when Claude is using its stock data folder.
    public let dataDirectory: URL?

    public init(pid: pid_t, dataDirectory: URL?) {
        self.pid = pid
        self.dataDirectory = dataDirectory
    }
}

/// Finds Claude instances by reading the process table. Each instance is started with a
/// distinct `--user-data-dir`, which is the only reliable way to tell them apart from outside.
public enum ProcessScanner {
    private static let flag = "--user-data-dir="

    /// Runs `ps` and returns the main process of every Claude instance.
    public static func scan(executablePath: String) -> [ClaudeProcess] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axww", "-o", "pid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        do { try ps.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        return parse(psOutput: String(decoding: data, as: UTF8.self), executablePath: executablePath)
    }

    /// Parses `ps -o pid=,command=` output.
    ///
    /// The stock instance must be the real executable. A profile instance may also run from a
    /// per-profile copy of the app (see `ProfileApps`), so any `…/Contents/MacOS/Claude` counts
    /// as long as it carries a `--user-data-dir`. Sibling binaries such as
    /// "Claude Helper --type=renderer" never match because the executable must be followed by
    /// a switch or nothing.
    public static func parse(psOutput: String, executablePath: String) -> [ClaudeProcess] {
        let executableName = (executablePath as NSString).lastPathComponent
        let bundleSuffix = "/Contents/MacOS/" + executableName

        let candidates: [ClaudeProcess] = psOutput.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " "), let pid = pid_t(line[..<space]) else {
                return nil
            }
            let command = line[line.index(after: space)...]
            guard let suffix = command.range(of: bundleSuffix) else { return nil }
            let executable = command[..<suffix.upperBound]
            let rest = command[suffix.upperBound...]
            guard rest.isEmpty || rest.hasPrefix(" -") else { return nil }
            // Chromium child processes (renderer, gpu, utility…) always carry --type=.
            guard !rest.contains(" --type=") else { return nil }

            let directory = dataDirectory(in: rest)
            guard executable == executablePath || directory != nil else { return nil }
            return ClaudeProcess(pid: pid, dataDirectory: directory)
        }
        // One entry per data folder; the main process is the oldest, hence the lowest pid.
        var byDirectory: [String: ClaudeProcess] = [:]
        for process in candidates.sorted(by: { $0.pid < $1.pid }) {
            let key = process.dataDirectory?.path ?? ""
            if byDirectory[key] == nil { byDirectory[key] = process }
        }
        return byDirectory.values.sorted { $0.pid < $1.pid }
    }

    /// Extracts the `--user-data-dir` value. Paths may contain spaces (`Application Support`),
    /// so the value runs until the next `--` switch or the end of the line.
    static func dataDirectory(in arguments: Substring) -> URL? {
        guard let start = arguments.range(of: flag) else { return nil }
        var value = arguments[start.upperBound...]
        if let next = value.range(of: " --") { value = value[..<next.lowerBound] }
        let path = value.trimmingCharacters(in: .whitespaces)
        return path.isEmpty ? nil : URL(fileURLWithPath: path).standardizedFileURL
    }
}

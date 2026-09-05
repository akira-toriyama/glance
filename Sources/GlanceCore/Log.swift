// glance verbose logging in the family shape (facet / chord / wand /
// perch): one `debugMode` global set at startup from the `GLANCE_DEBUG`
// env var. There is no `--debug` flag, so a normal pipe invocation cannot
// turn it on by accident; run.sh's --demo path opts in explicitly.
//
// `Log.line` has no caller in glance. It stays so the file keeps the
// family shape until sill's Log atom replaces all six copies (t-pggc).

import Foundation

/// Set once at startup by `GlanceApp.main` from the `GLANCE_DEBUG` env var.
/// Write-once at launch, then read-only.
nonisolated(unsafe) public var debugMode = false

public enum Log {
    public static let path = "/tmp/glance.log"

    public static func line(_ s: String) { emit(s, prefix: "") }

    public static func debug(_ s: String) {
        guard debugMode else { return }
        emit(s, prefix: "DEBUG ")
    }

    private static func emit(_ s: String, prefix: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let msg = "\(ts) \(prefix)\(s)\n"
        let data = Data(msg.utf8)
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            try? msg.write(toFile: path, atomically: false, encoding: .utf8)
        }
        if debugMode { FileHandle.standardError.write(data) }
    }
}

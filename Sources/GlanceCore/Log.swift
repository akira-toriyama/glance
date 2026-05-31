// glance verbose logging — mirrors the family convention (facet / chord /
// wand / eventfx / perch): a `debugMode` global, set once at startup from the
// `GLANCE_DEBUG` env var (run.sh's --demo path sets it; a normal pipe
// invocation stays quiet). There is no `--debug` flag.
//
// Two levels:
//   - `Log.line`  — always on (operational events worth seeing in a report).
//   - `Log.debug` — no-op unless `debugMode == true`. Use for arg parsing,
//                   stdin size, panel geometry, dismissal.
//
// Output:
//   - `/tmp/glance.log` — always (both levels).
//   - stderr — only when `debugMode == true`, so a normal pipe run stays
//     quiet and a `GLANCE_DEBUG=1 … | glance …` dev run streams live.

import Foundation

/// Set once at startup by `GlanceApp.main` from the `GLANCE_DEBUG` env var.
/// Write-once at launch, then read-only.
nonisolated(unsafe) public var debugMode = false

public enum Log {
    public static let path = "/tmp/glance.log"

    /// Always-on operational line. Also mirrors to stderr when GLANCE_DEBUG is set.
    public static func line(_ s: String) { emit(s, prefix: "") }

    /// Verbose log line. No-op unless `debugMode == true`.
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

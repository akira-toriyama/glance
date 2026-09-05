import LogKit

/// The process-wide logger: `/tmp/glance.log`, switched by `GLANCE_DEBUG`
/// (sill LogKit's family shape; there is no `--debug` flag). A global
/// `let`, not an injected value, because every layer logs and a one-shot
/// CLI has exactly one process to log for.
public let log = Log(app: "glance")

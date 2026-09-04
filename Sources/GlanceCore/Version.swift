/// The version `glance --version` prints. One declaration, read by
/// `GlanceApp` only (glance is a bare binary — no Info.plist to mirror).
///
/// Not derived from git on purpose: glyph's rolling draft cuts the release
/// tag on a commit that already exists and never rewrites the source, and
/// the Homebrew formula builds the tag's tarball (no `.git`, plain
/// `swift build`) and asserts this string against the formula version. So
/// the PR that moves the verdict bumps this constant to the tag the draft
/// targets (the version-preview comment names it); release.yml's
/// `version-sync` job fails the main run when the two differ. 0.2.0 sat
/// here through v0.3.0 and v1.0.0 before that job existed.
public enum GlanceVersion {
    public static let current = "1.0.1"
}

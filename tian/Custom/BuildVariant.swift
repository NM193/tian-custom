/// tian-custom: compile-time build variant. The Debug build is tian-dev, which
/// runs next to the installed release tian and must not touch what the release
/// app owns: its Sparkle updates and the skills it installs into ~/.claude/skills.
enum BuildVariant {
    #if DEBUG
    static let isDev = true
    #else
    static let isDev = false
    #endif
}

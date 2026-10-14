import AppKit

@main struct Checks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "Qingyu.AppearanceChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let theme = WorkspaceTheme(defaults: defaults)
        precondition(theme.selection == .system)
        theme.selection = .dark
        precondition(NSApp.appearance?.name == .darkAqua)
        precondition(WorkspaceTheme(defaults: defaults).selection == .dark)
        theme.selection = .light
        precondition(NSApp.appearance?.name == .aqua)
        precondition(WorkspaceTheme(defaults: defaults).selection == .light)
        theme.selection = .system
        precondition(NSApp.appearance == nil)
        precondition(WorkspaceTheme(defaults: defaults).selection == .system)
        defaults.set("unknown", forKey: WorkspaceTheme.key)
        precondition(WorkspaceTheme(defaults: defaults).selection == .system)
        print("Appearance checks passed: system default, native override, persistence, reset to system, invalid-value fallback")
    }
}

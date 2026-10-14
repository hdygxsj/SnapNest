import AppKit
import Carbon

final class Token {
    let release: () -> Void
    init(_ release: @escaping () -> Void) { self.release = release }
    deinit { release() }
}
@MainActor final class FakeRegistry {
    var active: [String: () -> Void] = [:]
    var reject = false
    func register(_ chord: AppShortcutChord, _ id: UInt32, _ action: @escaping () -> Void) -> AnyObject? {
        let key = chord.label
        guard !reject, active[key] == nil else { return nil }
        active[key] = action
        return Token { self.active[key] = nil }
    }
}
@main struct Checks {
    @MainActor static func main() {
        func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
        let suite = "SnapNest.ShortcutChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let registry = FakeRegistry()
        var store: AppShortcutStore? = AppShortcutStore(defaults: defaults, register: registry.register)
        let first = URL(fileURLWithPath: "/Applications/First.app")
        let second = URL(fileURLWithPath: "/Applications/Second.app")
        let a = AppShortcutChord(keyCode: 0, modifiers: UInt32(controlKey | optionKey))
        let b = AppShortcutChord(keyCode: 11, modifiers: UInt32(controlKey | optionKey))
        for code: UInt32 in [7,17,49] {
            check(AppShortcutChord(keyCode: code, modifiers: UInt32(cmdKey | shiftKey)).validationError != nil, "built-in keys reserved")
        }
        check(AppShortcutChord(keyCode: 0, modifiers: 0).validationError != nil, "bare letters rejected")
        check(AppShortcutChord(keyCode: 0, modifiers: UInt32(shiftKey)).validationError != nil, "shift-only rejected")
        check(!store!.save(url: URL(fileURLWithPath: "/tmp/folder"), title: "Folder", chord: a), "only apps supported")
        check(store!.save(url: first, title: "First", chord: a), "initial save")
        check(registry.active.count == 1, "registered while panel absent")
        var launched: String?
        store!.launch = { launched = $0.title }
        registry.active[a.label]?()
        check(launched == "First", "binding dispatches correct app")
        check(!store!.save(url: second, title: "Second", chord: a), "duplicate rejected")
        registry.reject = true
        check(!store!.save(url: first, title: "First", chord: b), "OS conflict rejected")
        check(store!.bindings.first?.chord == a && registry.active[a.label] != nil, "failed change preserves old registration")
        registry.reject = false
        check(store!.save(url: first, title: "First", chord: b), "replacement succeeds")
        check(registry.active[a.label] == nil && registry.active[b.label] != nil, "replacement releases previous key")
        store = nil
        check(registry.active.isEmpty, "registrations released at shutdown")
        store = AppShortcutStore(defaults: defaults, register: registry.register)
        check(store!.bindings.first?.chord == b, "binding survives restart")
        store!.start(); store!.start()
        check(registry.active.count == 1, "restore registers once")
        store!.remove(id: first.absoluteString)
        check(registry.active.isEmpty && store!.bindings.isEmpty, "clear releases key")
        check(AppShortcutStore(defaults: defaults, register: registry.register).bindings.isEmpty, "clear persists")
        check(store!.save(url: first, title: "First", chord: a), "save before restore failure")
        store = nil; registry.reject = true
        store = AppShortcutStore(defaults: defaults, register: registry.register); store!.start()
        check(store!.bindings.count == 1 && store!.failures[first.absoluteString] != nil, "restore failure visible without dropping binding")
        print("App shortcut checks passed: validation, dispatch, conflicts, rollback, persistence, replacement, removal, restore failure")
    }
}

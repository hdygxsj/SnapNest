import AppKit

@MainActor private final class WorkspaceTestTasks: TaskRepository {
    var authorized = false
    func requestAccess() async throws -> Bool { false }
    func availableLists() -> [TaskList] { [] }
    func sources() -> [TaskSource] { [] }
    func createList(sourceID: String) throws -> TaskList { throw TaskStoreError.message("Test only") }
    func fetch(listID: String) async throws -> [TaskEntry] { [] }
    func save(_ item: TaskEntry, listID: String) throws {}
}
@MainActor enum WorkspaceVerification {
    static func run() -> Bool {
        let a = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let b = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let saved = NSRect(x: -1700, y: 100, width: 1100, height: 800)
        guard WorkspacePlacement.frame(saved: saved, screens: [a,b]) == saved,
              a.contains(WorkspacePlacement.frame(saved: saved, screens: [a])!),
              WorkspacePlacement.frame(saved: nil, screens: [a])?.size == NSSize(width: 1000, height: 740),
              WorkspacePlacement.frame(saved: nil, screens: []) == nil,
              WorkspacePlacement.frame(saved: NSRect(x: 99999, y: 99999, width: 5000, height: 5000), screens: [a]) == a else {
            print("FAIL workspace placement"); return false
        }
        let right = NSRect(x: 820, y: 868, width: 620, height: 32)
        let badge = TaskBadgePlacement.frame(screen: a, visible: NSRect(x: 0, y: 0, width: 1440, height: 868), notchRight: right)
        let fallback = TaskBadgePlacement.frame(screen: b, visible: NSRect(x: -1920, y: 0, width: 1920, height: 1055), notchRight: nil)
        guard right.contains(badge), badge.minX == right.minX + 6,
              badge.width == 64, badge.height == 24,
              fallback.midX == b.midX, fallback.maxY == 1049,
              b.contains(fallback) else { print("FAIL task badge placement"); return false }
        let suite = "Qingyu.WindowCheck.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TaskCenterModel(repository: WorkspaceTestTasks(), defaults: defaults)
        guard TaskIslandController.verifyLifecycle(model: model, defaults: defaults) else { print("FAIL workspace lifecycle"); return false }
        print("Workspace passed: movable/resizable normal window, page switch, frame persistence, close/hide, capsule transition, capture suppression, relaunch restore, disconnected monitor clamping")
        return true
    }
}

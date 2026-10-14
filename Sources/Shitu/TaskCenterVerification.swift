// SnapNest v2 private additions. Original project MIT notices remain in LICENSE.
import Foundation

@MainActor
private final class FakeTaskRepository: TaskRepository {
    var authorized = true
    var requests = 0
    var failSave = false
    var failCreate = false
    var failFetch = false
    var lists = [TaskList(id: "dedicated", title: "SnapNest", source: "Test account")]
    var rows = [TaskEntry(id: "one", title: "Fixture", due: nil, completed: false)]
    var pending: [CheckedContinuation<[TaskEntry], Error>] = []
    var suspendFetch = false
    func requestAccess() async throws -> Bool { requests += 1; return authorized }
    func availableLists() -> [TaskList] { lists }
    func sources() -> [TaskSource] { [TaskSource(id: "source", title: "Test account")] }
    func createList(sourceID: String) throws -> TaskList {
        if failCreate { throw TaskStoreError.message("Fixture creation failed") }; return lists[0]
    }
    func fetch(listID: String) async throws -> [TaskEntry] {
        if failFetch { throw TaskStoreError.message("Fixture fetch failed") }
        if suspendFetch { return try await withCheckedThrowingContinuation { pending.append($0) } }
        return rows
    }
    func save(_ item: TaskEntry, listID: String) throws {
        if failSave { throw TaskStoreError.message("Fixture write failed") }
        if let i = rows.firstIndex(where: { $0.id == item.id }) { rows[i] = item } else { rows.append(item) }
    }
}

@MainActor
enum TaskCenterVerification {
    static func run() async -> Bool {
        let repo = FakeTaskRepository()
        let suite = "SnapNest.TaskVerification.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TaskCenterModel(repository: repo, defaults: defaults)
        func check(_ value: Bool, _ label: String) -> Bool {
            if !value { print("FAIL Tasks: \(label)") }; return value
        }
        await model.refresh()
        guard check(repo.requests == 0 && model.items.isEmpty, "refresh cannot request access or bind arbitrary list") else { return false }
        model.requestComposer(text: "Selected text")
        guard check(model.draft == nil && model.pendingDraft?.title == "Selected text", "onboarding keeps selected text without blocking setup") else { return false }
        repo.failCreate = true
        await model.createList(sourceID: "source")
        guard check(model.boundList == nil && model.error != nil, "list creation failure visible") else { return false }
        repo.failCreate = false
        model.bind(repo.lists[0])
        await model.refresh()
        guard check(model.items.count == 1, "explicit list binding fetches") else { return false }
        guard check(model.draft?.title == "Selected text" && model.pendingDraft == nil, "composer resumes after explicit setup") else { return false }
        model.requestComposer(text: "Replacement")
        guard check(model.draft?.title == "Selected text" && model.composerNotice != nil, "new capture cannot overwrite unsaved draft") else { return false }
        let firstSession = model.draft!.sessionID
        model.updateDraft(sessionID: firstSession, title: "Typed text", due: nil)
        model.chooseAnotherList()
        guard check(model.pendingDraft?.title == "Typed text" && model.draft == nil, "list switching preserves typed draft") else { return false }
        model.bind(repo.lists[0]); await model.refresh()
        model.finishDraft(sessionID: firstSession)
        model.requestComposer(text: "New session")
        guard check(model.draft?.sessionID != firstSession, "new draft has independent UI identity") else { return false }
        model.finishDraft(sessionID: firstSession)
        guard check(model.draft?.title == "New session", "old completion cannot dismiss new draft") else { return false }
        repo.suspendFetch = true
        let savingSession = model.draft!.sessionID
        let saving = Task { @MainActor in
            if await model.save(model.draft!) { model.finishDraft(sessionID: savingSession) }
        }
        while repo.pending.isEmpty { await Task.yield() }
        model.requestComposer(text: "Captured during save")
        guard check(model.draft?.title == "New session" && model.composerNotice != nil, "capture during async save is explicitly rejected without overwrite") else { return false }
        repo.pending.removeFirst().resume(returning: repo.rows)
        await saving.value
        repo.suspendFetch = false
        model.requestComposer(text: "After save")
        model.finishDraft(sessionID: savingSession)
        guard check(model.draft?.title == "After save", "completed async save cannot close later session") else { return false }
        let due = Date(timeIntervalSince1970: 1_800_000_123)
        let completed = TaskEntry(id: "one", title: "Fixture", due: due, completed: true)
        guard await model.save(completed), check(model.items.first(where: { $0.id == "one" })?.due == due && model.items.first(where: { $0.id == "one" })?.completed == true, "save preserves full due value and completion") else { return false }
        repo.failFetch = true
        await model.refresh()
        guard check(model.error != nil && !model.dataAvailable, "fetch failure marks count unavailable") else { return false }
        repo.failFetch = false
        repo.failSave = true
        let saved = await model.save(TaskEntry(id: "one", title: "Changed", due: nil, completed: true))
        guard check(!saved && model.items.first(where: { $0.id == "one" })?.title == "Fixture" && model.error != nil, "failed write preserves task") else { return false }
        repo.suspendFetch = true
        let older = Task { await model.refresh() }
        while repo.pending.isEmpty { await Task.yield() }
        let newer = Task { await model.refresh() }
        while repo.pending.count < 2 { await Task.yield() }
        repo.pending[1].resume(returning: [TaskEntry(id: "new", title: "Newest", due: nil, completed: false)])
        await newer.value
        repo.pending[0].resume(returning: [])
        await older.value
        guard check(model.items.first?.title == "Newest", "stale fetch discarded") else { return false }
        repo.suspendFetch = false
        repo.authorized = false
        await model.refresh()
        guard check(model.items.isEmpty && model.error != nil, "revocation clears cached data") else { return false }
        await model.connect()
        guard check(repo.requests == 1 && model.error != nil, "denial visible") else { return false }
        repo.authorized = true; repo.lists = []
        await model.refresh()
        guard check(model.boundList == nil && model.items.isEmpty, "deleted list unbound") else { return false }
        print("Tasks verified: explicit binding, no implicit permission, failed writes, stale fetch, revocation, missing list (fake store only)")
        return true
    }
}

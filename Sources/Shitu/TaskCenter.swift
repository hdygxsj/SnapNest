// SnapNest v2 private additions. Original project MIT notices remain in LICENSE.
import AppKit
import SwiftUI
import EventKit
import Combine

struct TaskEntry: Identifiable, Equatable {
    var sessionID = UUID()
    var id: String
    var title: String
    var due: Date?
    var completed: Bool
}
struct TaskList: Identifiable, Equatable { var id: String; var title: String; var source: String }
struct TaskSource: Identifiable { var id: String; var title: String }
enum TaskStoreError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
@MainActor protocol TaskRepository: AnyObject {
    var authorized: Bool { get }
    func requestAccess() async throws -> Bool
    func availableLists() -> [TaskList]
    func sources() -> [TaskSource]
    func createList(sourceID: String) throws -> TaskList
    func fetch(listID: String) async throws -> [TaskEntry]
    func save(_ item: TaskEntry, listID: String) throws
}

@MainActor final class EventKitTaskRepository: TaskRepository {
    let store = EKEventStore()
    var authorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToReminders() }
    private func summary(_ list: EKCalendar) -> TaskList {
        TaskList(id: list.calendarIdentifier, title: list.title, source: list.source.title)
    }
    func availableLists() -> [TaskList] {
        guard authorized else { return [] }
        return store.calendars(for: .reminder).filter { $0.allowsContentModifications && $0.title == "SnapNest" }.map(summary)
    }
    func sources() -> [TaskSource] {
        guard authorized else { return [] }
        return store.sources.filter { $0.sourceType == .local || $0.sourceType == .calDAV || $0.sourceType == .exchange }
            .map { TaskSource(id: $0.sourceIdentifier, title: $0.title) }
    }
    func createList(sourceID: String) throws -> TaskList {
        guard authorized, let source = store.source(withIdentifier: sourceID) else { throw TaskStoreError.message("账户不可用，请重新连接提醒事项。") }
        if let existing = store.calendars(for: .reminder).first(where: { $0.source.sourceIdentifier == sourceID && $0.title == "SnapNest" && $0.allowsContentModifications }) { return summary(existing) }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = "SnapNest"; list.source = source
        try store.saveCalendar(list, commit: true)
        return summary(list)
    }
    private func calendar(_ id: String) throws -> EKCalendar {
        guard authorized else { throw TaskStoreError.message("提醒事项访问权限已关闭，请在系统设置中允许访问。") }
        guard let list = store.calendar(withIdentifier: id), list.allowsContentModifications,
              list.allowedEntityTypes.contains(.reminder) else { throw TaskStoreError.message("SnapNest 列表已删除或不可写，请重新选择。") }
        return list
    }
    func fetch(listID: String) async throws -> [TaskEntry] {
        let list = try calendar(listID)
        let predicate = store.predicateForReminders(in: [list])
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { rows in
                guard let rows else { continuation.resume(throwing: TaskStoreError.message("无法读取提醒事项，请重试。")); return }
                continuation.resume(returning: rows.map {
                    TaskEntry(id: $0.calendarItemIdentifier, title: $0.title ?? "", due: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) }, completed: $0.isCompleted)
                })
            }
        }
    }
    func save(_ item: TaskEntry, listID: String) throws {
        let list = try calendar(listID)
        let reminder: EKReminder
        if item.id.isEmpty { reminder = EKReminder(eventStore: store); reminder.calendar = list }
        else {
            guard let existing = store.calendarItem(withIdentifier: item.id) as? EKReminder,
                  existing.calendar.calendarIdentifier == listID else { throw TaskStoreError.message("任务已移走或删除，请刷新。") }
            reminder = existing
        }
        reminder.title = item.title
        let existingDue = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        if existingDue != item.due {
            reminder.dueDateComponents = item.due.map { Calendar.current.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: $0) }
        }
        reminder.isCompleted = item.completed
        try store.save(reminder, commit: true)
    }
}

@MainActor final class TaskCenterModel: ObservableObject {
    @Published var dataAvailable = false
    @Published var composerNotice: String?
    @Published var items: [TaskEntry] = []
    @Published var lists: [TaskList] = []
    @Published var sources: [TaskSource] = []
    @Published var boundList: TaskList?
    @Published var error: String?
    @Published var connected = false
    @Published var busy = false
    @Published var islandEnabled: Bool { didSet { defaults.set(islandEnabled, forKey: "tasks.islandEnabled") } }
    @Published var draft: TaskEntry?
    @Published var pendingDraft: TaskEntry?
    private let repository: TaskRepository
    private let defaults: UserDefaults
    private var listID: String?
    private var generation = 0
    var unfinishedCount: Int { items.filter { !$0.completed }.count }
    init(repository: TaskRepository, defaults: UserDefaults = .standard) {
        self.repository = repository; self.defaults = defaults
        listID = defaults.string(forKey: "tasks.listID")
        islandEnabled = defaults.object(forKey: "tasks.islandEnabled") as? Bool ?? true
    }
    func connect() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard try await repository.requestAccess() else { error = "未获得提醒事项权限。请在系统设置 → 隐私与安全性 → 提醒事项中允许 SnapNest。"; connected = false; items = []; return }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func requestComposer(text: String = "") {
        guard draft == nil, pendingDraft == nil, !busy else { composerNotice = "已有未保存任务或正在保存，请先保存或取消当前任务，再重新捕获。"; return }
        composerNotice = nil
        let entry = TaskEntry(id: "", title: text, due: nil, completed: false)
        if connected && boundList != nil { draft = entry } else { pendingDraft = entry }
    }
    func finishDraft(sessionID: UUID) {
        guard draft?.sessionID == sessionID else { return }
        draft = nil; composerNotice = nil
    }
    func updateDraft(sessionID: UUID, title: String, due: Date?) {
        guard draft?.sessionID == sessionID else { return }
        draft?.title = title; draft?.due = due
    }
    func chooseAnotherList() {
        guard !busy else { return }
        if let current = draft { pendingDraft = current; draft = nil }
        dataAvailable = false
        generation += 1; listID = nil; boundList = nil; items = []; error = nil
        defaults.removeObject(forKey: "tasks.listID")
    }
    func bind(_ list: TaskList) {
        dataAvailable = false
        generation += 1; listID = list.id; boundList = list; items = []; error = nil
        defaults.set(list.id, forKey: "tasks.listID")
    }
    func createList(sourceID: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { bind(try repository.createList(sourceID: sourceID)); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        generation += 1; let request = generation
        connected = repository.authorized
        guard connected else { dataAvailable = false; items = []; boundList = nil; lists = []; sources = []; if listID != nil { error = "提醒事项访问权限已关闭，请重新连接或检查系统设置。" }; return }
        lists = repository.availableLists(); sources = repository.sources()
        guard let id = listID else { return }
        guard let list = lists.first(where: { $0.id == id }) else {
            dataAvailable = false; items = []; boundList = nil; listID = nil; defaults.removeObject(forKey: "tasks.listID")
            error = "原 SnapNest 列表已删除、改名或不可写，请重新选择或创建。"; return
        }
        boundList = list
        if draft == nil, let pending = pendingDraft { draft = pending; pendingDraft = nil }
        do {
            let rows = try await repository.fetch(listID: id)
            guard request == generation, listID == id else { return }
            guard repository.authorized else { dataAvailable = false; items = []; boundList = nil; connected = false; error = "提醒事项权限已关闭。"; return }
            dataAvailable = true
            items = rows.sorted { a, b in
                if a.completed != b.completed { return !a.completed }
                if a.due != b.due { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }; error = nil
        } catch { if request == generation { self.dataAvailable = false; self.error = error.localizedDescription } }
    }
    func save(_ entry: TaskEntry) async -> Bool {
        guard !busy, let id = listID, boundList != nil else { return false }
        var item = entry; item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty else { error = "请输入任务标题。"; return false }
        busy = true; defer { busy = false }
        do { try repository.save(item, listID: id); await refresh(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

@MainActor final class TaskCenterController {
    let model: TaskCenterModel
    private var island: TaskIslandController?
    var captureContent: AnyView?
    var settingsContent: AnyView?
    private var observers: [NSObjectProtocol] = []
    private var subscriptions: Set<AnyCancellable> = []
    init(repository: TaskRepository? = nil, defaults: UserDefaults = .standard) {
        model = TaskCenterModel(repository: repository ?? EventKitTaskRepository(), defaults: defaults)
    }
    func start() {
        guard island == nil else { return }
        island = TaskIslandController(model: model, launcher: QuickLauncherController.shared, captureContent: captureContent, settingsContent: settingsContent)
        for name in [Notification.Name.EKEventStoreChanged, NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.model.refresh() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        })
        Task { await model.refresh() }
    }
    func showComposer(text: String = "") {
        model.requestComposer(text: text); showTasks()
    }
    func showTasks() {
        if island == nil { start() }
        island?.expand(.tasks)
        Task { await model.refresh() }
    }
    func showPage(_ page: IslandPage) { if island == nil { start() }; island?.expand(page) }
    func setCaptureActive(_ active: Bool) { island?.setCaptureActive(active) }

}

struct TaskCenterView: View {
    @ObservedObject var model: TaskCenterModel
    @State private var sourceID = ""
    var body: some View {
        Group {
            if let draft = model.draft {
                TaskDraftView(model: model, original: draft).id(draft.sessionID)
            } else { content }
        }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("我的待办").font(.title2.bold()); Spacer(); Button("刷新") { Task { await model.refresh() } } }
            if !model.connected || model.boundList == nil { Text("任务保存在系统提醒事项中。跨设备同步需选择 iCloud 账户，并在各设备开启同一 Apple 账户的提醒事项同步；其他账户不一定同步到 iPhone。")
                .font(.caption).foregroundStyle(.secondary) }
            if let notice = model.composerNotice { Text(notice).foregroundStyle(.orange).font(.callout) }
            if let error = model.error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            if let pending = model.pendingDraft {
                HStack {
                    Text("待添加：\(pending.title.isEmpty ? "新任务" : pending.title)").lineLimit(2)
                    Spacer(); Button("取消添加") { model.pendingDraft = nil }
                }.font(.callout)
            }
            if !model.connected {
                Button("连接系统提醒事项") { Task { await model.connect() } }.buttonStyle(.borderedProminent)
            } else if let list = model.boundList {
                HStack {
                    Text("\(list.title) · \(list.source)").font(.callout).foregroundStyle(.secondary)
                    Spacer(); Button("切换列表") { model.chooseAnotherList() }
                }
                HStack {
                    Button("添加任务") { model.requestComposer() }
                    Spacer(); Text(model.dataAvailable ? "\(model.unfinishedCount) 项未完成" : "任务状态暂不可用").foregroundStyle(.secondary)
                }
                List(model.dataAvailable ? model.items : []) { item in
                    HStack {
                        Button { var next = item; next.completed.toggle(); Task { _ = await model.save(next) } } label: {
                            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(.plain).accessibilityLabel(item.completed ? "标为未完成" : "完成任务")
                        VStack(alignment: .leading) {
                            Text(item.title).strikethrough(item.completed)
                            if let due = item.due { Text(due, style: .date).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(); Button("编辑") { model.draft = item }
                    }.padding(.vertical, 3).listRowBackground(Color.primary.opacity(0.04))
                }.scrollContentBackground(.hidden)
            } else {
                Text("选择专用 SnapNest 列表，或在指定账户创建新列表。")
                ForEach(model.lists) { list in
                    Button("使用 \(list.title) · \(list.source)") { model.bind(list); Task { await model.refresh() } }
                }
                Picker("账户", selection: $sourceID) {
                    Text("请选择账户").tag("")
                    ForEach(model.sources) { source in Text(source.title).tag(source.id) }
                }
                Button("创建 SnapNest 列表") { Task { await model.createList(sourceID: sourceID) } }.disabled(sourceID.isEmpty)
                if model.sources.isEmpty { Text("没有可用账户。请先在系统提醒事项中配置账户，再刷新。") }
            }
            Spacer(minLength: 0)
            Toggle("显示屏幕顶部任务计数", isOn: $model.islandEnabled)
        }.padding(22).frame(minWidth: 420, minHeight: 400)
            .disabled(model.busy)

    }
}
private struct TaskDraftView: View {
    @ObservedObject var model: TaskCenterModel
    let original: TaskEntry
    @State private var title = ""
    @State private var hasDue = false
    @State private var due = Date()
    private func syncDraft() { model.updateDraft(sessionID: original.sessionID, title: title, due: hasDue ? due : nil) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(original.id.isEmpty ? "新任务" : "编辑任务").font(.title2.bold())
            TextField("任务标题", text: $title, axis: .vertical).lineLimit(3...8)
            Button("粘贴") { if let text = NSPasteboard.general.string(forType: .string) { title = text } }
            Toggle("设置截止日期", isOn: $hasDue)
            if hasDue { DatePicker("截止日期", selection: $due, displayedComponents: [.date, .hourAndMinute]) }
            if let notice = model.composerNotice { Text(notice).foregroundStyle(.orange) }
            if model.boundList == nil { Text("请取消并先连接提醒事项、选择 SnapNest 列表。新任务尚未保存。").foregroundStyle(.secondary) }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("取消") { model.finishDraft(sessionID: original.sessionID) }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Spacer()
                Button("保存") {
                    var item = original; item.title = title; item.due = hasDue ? due : nil
                    Task { if await model.save(item) { model.finishDraft(sessionID: original.sessionID) } }
                }.keyboardShortcut(.defaultAction).disabled(model.boundList == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            }
        }.padding(24).frame(width: 420)
            .disabled(model.busy)
            .onChange(of: title) { _, _ in syncDraft() }
            .onChange(of: hasDue) { _, _ in syncDraft() }
            .onChange(of: due) { _, _ in syncDraft() }
            .onAppear { title = original.title; hasDue = original.due != nil; due = original.due ?? Date() }
    }
}

/// Preview-only store: never creates EKEventStore or accesses user reminders.
@MainActor private final class TaskPreviewRepository: TaskRepository {
    var authorized: Bool { false }
    func requestAccess() async throws -> Bool { false }
    func availableLists() -> [TaskList] { [] }
    func sources() -> [TaskSource] { [] }
    func createList(sourceID: String) throws -> TaskList { throw TaskStoreError.message("Preview") }
    func fetch(listID: String) async throws -> [TaskEntry] { [] }
    func save(_ item: TaskEntry, listID: String) throws { throw TaskStoreError.message("Preview") }
}
@MainActor enum TaskCenterPreview {
    static func render(to directory: String) -> Bool {
        _ = NSApplication.shared
        let suite = "SnapNest.TaskPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TaskCenterModel(repository: TaskPreviewRepository(), defaults: defaults)
        let onboarding = renderView(TaskCenterView(model: model), name: "tasks-onboarding", directory: directory, size: NSSize(width: 560, height: 620))
        model.connected = true; model.dataAvailable = true
        model.boundList = TaskList(id: "preview-list", title: "SnapNest", source: "示例 iCloud 账户")
        model.items = [
            TaskEntry(id: "preview-1", title: "整理今天的产品讨论与下一步计划", due: Date(), completed: false),
            TaskEntry(id: "preview-2", title: "检查截图标注与导出效果", due: nil, completed: false),
            TaskEntry(id: "preview-3", title: "完成设计评审", due: nil, completed: true)
        ]
        let tasks = renderView(TaskCenterView(model: model), name: "tasks-list", directory: directory, size: NSSize(width: 560, height: 620))
        let composer = renderView(TaskDraftView(model: model, original: TaskEntry(id: "", title: "把选中的文字变为下一项任务", due: Date(), completed: false)), name: "tasks-composer", directory: directory, size: NSSize(width: 480, height: 360))
        let island = renderView(TaskIslandView(model: model, open: {}), name: "tasks-island", directory: directory, size: NSSize(width: 188, height: 56))
        let launcher = QuickLauncherController()
        let controller = TaskIslandController(model: model, launcher: launcher, preview: true)
        controller.expanded = true; controller.page = .tasks
        let unifiedTasks = renderView(UnifiedIslandView(controller: controller, model: model, launcher: launcher), name: "unified-tasks", directory: directory, size: NSSize(width: 600, height: 570))
        controller.page = .launcher
        let unifiedLauncher = renderView(UnifiedIslandView(controller: controller, model: model, launcher: launcher), name: "unified-launcher", directory: directory, size: NSSize(width: 600, height: 570))
        var themes = true
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            controller.expanded = true; controller.page = .tasks
            themes = renderView(UnifiedIslandView(controller: controller, model: model, launcher: launcher), name: "workspace-" + (dark ? "dark" : "light"), directory: directory, size: NSSize(width: 600, height: 570), appearance: appearance) && themes
            controller.expanded = false
            themes = renderView(UnifiedIslandView(controller: controller, model: model, launcher: launcher), name: "count-" + (dark ? "dark" : "light"), directory: directory, size: NSSize(width: 192, height: 38), appearance: appearance) && themes
        }
        return onboarding && tasks && composer && island && unifiedTasks && unifiedLauncher && themes
    }
    private static func renderView<V: View>(_ root: V, name: String, directory: String, size: NSSize, appearance: NSAppearance? = nil) -> Bool {
        let view = NSHostingView(rootView: root.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            return true
        } catch { print("Task preview failed: \(error)"); return false }
    }
}

// SnapNest 2.0 private additions.
import AppKit
import Carbon
import SwiftUI

struct AppShortcutChord: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    static let keys: [(String, UInt32)] = [
        ("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),("H",4),("I",34),("J",38),("K",40),("L",37),("M",46),
        ("N",45),("O",31),("P",35),("Q",12),("R",15),("S",1),("T",17),("U",32),("V",9),("W",13),("X",7),("Y",16),("Z",6),
        ("0",29),("1",18),("2",19),("3",20),("4",21),("5",23),("6",22),("7",26),("8",28),("9",25),
        ("Space",49),("F1",122),("F2",120),("F3",99),("F4",118),("F5",96),("F6",97),("F7",98),("F8",100),("F9",101),("F10",109),("F11",103),("F12",111)
    ]
    var label: String {
        [(controlKey,"⌃"),(optionKey,"⌥"),(shiftKey,"⇧"),(cmdKey,"⌘")].filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined()
        + (Self.keys.first { $0.1 == keyCode }?.0 ?? "?")
    }
    var validationError: String? {
        let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        guard modifiers & ~supported == 0, Self.keys.contains(where: { $0.1 == keyCode }) else { return "不支持这个按键组合。" }
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else { return "请至少选择 ⌘、⌃ 或 ⌥ 中的一个修饰键。" }
        if modifiers == UInt32(cmdKey | shiftKey), [7,17,49].contains(keyCode) { return "此组合已用于截图、划词待办或启动面板。" }
        if (modifiers == UInt32(cmdKey) && [0,8,9,12,13,48,49,50].contains(keyCode)) ||
            (keyCode == 49 && [UInt32(controlKey), UInt32(optionKey | cmdKey)].contains(modifiers)) ||
            (modifiers == UInt32(cmdKey | shiftKey) && [20,21,23].contains(keyCode)) {
            return "此组合是常用系统快捷键，请换一个组合。"
        }
        return nil
    }
}

struct AppShortcutBinding: Codable, Identifiable {
    let url: URL
    let title: String
    var chord: AppShortcutChord
    var id: String { url.absoluteString }
}

@MainActor final class AppShortcutStore: ObservableObject {
    typealias Register = (AppShortcutChord, UInt32, @escaping () -> Void) -> AnyObject?
    @Published private(set) var bindings: [AppShortcutBinding] = []
    @Published private(set) var failures: [String: String] = [:]
    @Published var error: String?
    var launch: ((AppShortcutBinding) -> Void)?
    private let defaults: UserDefaults
    private let register: Register
    private var registrations: [String: AnyObject] = [:]
    private var nextIdentifier: UInt32 = 100
    private var started = false
    static let storageKey = "snapnest.v2.appShortcuts"
    init(defaults: UserDefaults = .standard, register: Register? = nil) {
        self.defaults = defaults
        self.register = register ?? { chord, id, action in
            let key = HotKey(); key.action = action
            return key.register(keyCode: chord.keyCode, modifiers: chord.modifiers, identifier: id) ? key : nil
        }
        if let data = defaults.data(forKey: Self.storageKey) {
            do { bindings = try JSONDecoder().decode([AppShortcutBinding].self, from: data) }
            catch { self.error = "无法读取应用快捷键配置。" }
        }
    }
    func start() {
        guard !started else { return }; started = true
        for binding in bindings {
            if let invalid = binding.chord.validationError { failures[binding.id] = invalid; continue }
            guard binding.url.isFileURL, binding.url.pathExtension.lowercased() == "app" else { failures[binding.id] = "目标不是应用程序。"; continue }
            if registrations[binding.id] != nil { continue }
            if let token = makeRegistration(binding) { registrations[binding.id] = token }
            else { failures[binding.id] = "快捷键注册失败，可能已被其他应用占用。" }
        }
    }
    @discardableResult func save(url: URL, title: String, chord: AppShortcutChord) -> Bool {
        error = nil
        guard url.isFileURL, url.pathExtension.lowercased() == "app" else { error = "请选择应用程序。"; return false }
        if let invalid = chord.validationError { error = invalid; return false }
        let id = url.absoluteString
        if let duplicate = bindings.first(where: { $0.id != id && $0.chord == chord }) { error = "此快捷键已分配给 \(duplicate.title)。"; return false }
        if bindings.first(where: { $0.id == id })?.chord == chord, registrations[id] != nil { return true }
        let binding = AppShortcutBinding(url: url, title: title, chord: chord)
        // Register the replacement before releasing the previous shortcut.
        guard let token = makeRegistration(binding) else { error = "快捷键注册失败，可能已被其他应用占用；原快捷键保持不变。"; return false }
        var updated = bindings.filter { $0.id != id }; updated.append(binding)
        guard persist(updated) else { return false }
        registrations[id] = token; bindings = updated; failures[id] = nil
        return true
    }
    func remove(id: String) {
        let updated = bindings.filter { $0.id != id }
        guard persist(updated) else { return }
        registrations[id] = nil; bindings = updated; failures[id] = nil; error = nil
    }
    private func makeRegistration(_ binding: AppShortcutBinding) -> AnyObject? {
        nextIdentifier += 1
        return register(binding.chord, nextIdentifier) { [weak self] in self?.launch?(binding) }
    }
    private func persist(_ values: [AppShortcutBinding]) -> Bool {
        do { defaults.set(try JSONEncoder().encode(values), forKey: Self.storageKey); return true }
        catch { self.error = "保存快捷键失败：\(error.localizedDescription)"; return false }
    }
}

struct AppShortcutEditor: View {
    @ObservedObject var store: AppShortcutStore
    let url: URL
    let title: String
    let close: () -> Void
    @State private var keyCode: UInt32 = 0
    @State private var modifiers = UInt32(controlKey | optionKey)
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(title) · 启动快捷键").font(.title2.bold())
            Text("选择组合后，在其他应用中按下也能直接启动或切换到这个 App。").foregroundStyle(.secondary)
            HStack {
                ForEach([("⌃ Control",UInt32(controlKey)),("⌥ Option",UInt32(optionKey)),("⇧ Shift",UInt32(shiftKey)),("⌘ Command",UInt32(cmdKey))], id: \.1) { title, mask in
                    Button {
                        if modifiers & mask == 0 { modifiers |= mask } else { modifiers &= ~mask }
                    } label: {
                        Label(title, systemImage: modifiers & mask != 0 ? "checkmark.circle.fill" : "circle")
                            .font(.caption).padding(8)
                            .background(modifiers & mask != 0 ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }.accessibilityValue(modifiers & mask != 0 ? "已选择" : "未选择")
                }
            }
            Picker("按键", selection: $keyCode) { ForEach(AppShortcutChord.keys, id: \.1) { Text($0.0).tag($0.1) } }.pickerStyle(.menu).buttonStyle(.bordered).frame(width: 220)
            Text(AppShortcutChord(keyCode: keyCode, modifiers: modifiers).label).font(.largeTitle.monospaced())
            Text("建议使用 ⌃⌥ 加字母，避免覆盖其他应用的常用操作。").font(.caption).foregroundStyle(.secondary)
            if let error = store.error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                if store.bindings.contains(where: { $0.id == url.absoluteString }) {
                    Button("清除快捷键") { store.remove(id: url.absoluteString); if store.error == nil { close() } }
                }
                Spacer()
                Button("取消", action: close)
                Button("保存") { if store.save(url: url, title: title, chord: AppShortcutChord(keyCode: keyCode, modifiers: modifiers)) { close() } }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                store.error = nil
                if let binding = store.bindings.first(where: { $0.id == url.absoluteString }) { keyCode = binding.chord.keyCode; modifiers = binding.chord.modifiers }
            }
    }
}

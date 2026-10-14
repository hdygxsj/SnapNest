import AppKit
import SwiftUI

enum WorkspaceAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" } }
    var native: NSAppearance? { switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) } }
}

@MainActor final class WorkspaceTheme: ObservableObject {
    static let shared = WorkspaceTheme()
    private let defaults: UserDefaults
    static let key = "snapnest.workspace.appearance"
    @Published var selection: WorkspaceAppearance {
        didSet { defaults.set(selection.rawValue, forKey: Self.key); apply() }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = WorkspaceAppearance(rawValue: defaults.string(forKey: Self.key) ?? "") ?? .system
    }
    func apply() { NSApp.appearance = selection.native }
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.55, green: 0.48, blue: 1) : Color(red: 0.10, green: 0.43, blue: 0.94) }
    static func surface(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.115, green: 0.12, blue: 0.16) : Color(red: 0.97, green: 0.975, blue: 0.985) }
}

struct Keycap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
    }
}

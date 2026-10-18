import SwiftUI
import ShituCore

@MainActor final class CaptureQualityPreferences: ObservableObject {
    static let shared = CaptureQualityPreferences()
    private let defaults: UserDefaults
    @Published var prefersHD: Bool {
        didSet { defaults.set(prefersHD, forKey: "qingyu.capture.preferHD") }
    }
    var quality: ExportQuality { prefersHD ? .highDefinition : .standard }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prefersHD = defaults.object(forKey: "qingyu.capture.preferHD") as? Bool
            ?? defaults.object(forKey: "qingyu.pro.preferHD") as? Bool ?? true
    }
}

struct CaptureQualitySettings: View {
    @ObservedObject var store: CaptureQualityPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导出画质").font(.title3.bold())
            Toggle("默认使用高清画质", isOn: $store.prefersHD)
            Text("高清 PNG 保留 Retina 原始像素；GIF 最高 1920 像素 / 20 fps。")
                .font(.caption).foregroundStyle(.secondary)
            Text("关闭后使用标准画质：PNG 逻辑尺寸，GIF 960 像素 / 10 fps，文件更小。GIF 最多支持 256 色，实际分辨率不超过录制源。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

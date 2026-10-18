import Foundation

@MainActor enum CaptureQualityVerification {
    static func run() -> Bool {
        let name = "Qingyu.FreeQualityCheck." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let fresh = CaptureQualityPreferences(defaults: defaults)
        guard fresh.quality == .highDefinition,
              fresh.quality.pngScale(nativeScale: 2) == 2,
              fresh.quality.gifMaximumDimension == 1920,
              fresh.quality.gifFramesPerSecond == 20 else { return false }
        defaults.set(false, forKey: "qingyu.pro.preferHD")
        let migrated = CaptureQualityPreferences(defaults: defaults)
        guard migrated.quality == .standard else { return false }
        migrated.prefersHD = true
        guard CaptureQualityPreferences(defaults: defaults).quality == .highDefinition else { return false }
        migrated.prefersHD = false
        guard CaptureQualityPreferences(defaults: defaults).quality == .standard else { return false }
        print("Free quality passed: HD default, Retina PNG, HD GIF, legacy preference migration and persistence")
        return true
    }
}

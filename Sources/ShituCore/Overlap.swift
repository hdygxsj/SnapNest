import Foundation

public enum OverlapMatcher {
    /// Matches downward scroll, ignoring outer edges and fixed header/footer bands.
    /// Returns new pixel rows; nil means uncertain, never append an uncertain frame.
    public static func displacement(previous: [UInt8], next: [UInt8], width: Int, height: Int) -> Int? {
        guard width >= 8, height >= 32, previous.count == width * height, next.count == previous.count else { return nil }
        if previous == next { return 0 }
        let margin = height / 8
        let xMargin = max(2, width / 8)
        var low = 255, high = 0
        for y in stride(from: margin, to: height - margin, by: max(1, height / 60)) {
            for x in stride(from: xMargin, to: width - xMargin, by: 2) {
                let pixel = Int(next[y * width + x])
                low = min(low, pixel); high = max(high, pixel)
            }
        }
        guard high - low > 18 else { return nil }
        func error(_ shift: Int) -> Double {
            let end = height - shift - margin
            guard end > margin + height / 10 else { return .infinity }
            var total = 0, count = 0
            for y in stride(from: margin, to: end, by: max(1, (end - margin) / 48)) {
                for x in stride(from: xMargin, to: width - xMargin, by: 2) {
                    total += abs(Int(previous[(y + shift) * width + x]) - Int(next[y * width + x]))
                    count += 1
                }
            }
            return Double(total) / Double(max(1, count))
        }
        if error(0) < 1.2 { return 0 }
        let scores = (1...max(1, height * 3 / 5)).map { ($0, error($0)) }
        guard let best = scores.min(by: { $0.1 < $1.1 }), best.1 < 9 else { return nil }
        let competitor = scores.filter { abs($0.0 - best.0) > 3 }.map(\.1).min() ?? .infinity
        guard competitor > best.1 * 1.25 + 0.6 else { return nil }
        return best.0
    }
}

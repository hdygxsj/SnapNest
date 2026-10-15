import AppKit

/// Keeps a restored workspace reachable when monitors or resolutions change.
enum WorkspacePlacement {
    static func frame(saved: NSRect?, screens: [NSRect]) -> NSRect? {
        guard let primary = screens.first else { return nil }
        let valid = saved.flatMap { rect -> NSRect? in
            guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }), rect.width >= 400, rect.height >= 300 else { return nil }
            return rect
        }
        let screen = valid.flatMap { rect in screens.max(by: { area($0.intersection(rect)) < area($1.intersection(rect)) }).flatMap { area($0.intersection(rect)) > 0 ? $0 : nil } } ?? primary
        let width = min(screen.width, max(800, valid?.width ?? 1000))
        let height = min(screen.height, max(622, valid?.height ?? 740))
        return NSRect(x: min(max(valid?.minX ?? screen.midX - width/2, screen.minX), screen.maxX - width),
                      y: min(max(valid?.minY ?? screen.midY - height/2, screen.minY), screen.maxY - height), width: width, height: height)
    }
    private static func area(_ rect: NSRect) -> CGFloat { rect.isNull ? 0 : max(0, rect.width) * max(0, rect.height) }
}

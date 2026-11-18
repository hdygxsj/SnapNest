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

/// NSScreen auxiliary areas use global screen coordinates, including secondary displays.
enum TaskBadgePlacement {
    static func frame(screen: NSRect, visible: NSRect, notchRight: NSRect?) -> NSRect {
        let size = NSSize(width: 64, height: 24)
        if let right = notchRight, right.width >= size.width + 12, right.height >= size.height {
            return NSRect(x: right.minX + 6, y: right.midY - size.height / 2, width: size.width, height: size.height)
        }
        return NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 6,
                      width: size.width, height: size.height)
    }
}

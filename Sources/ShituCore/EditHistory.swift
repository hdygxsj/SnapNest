public struct EditHistory<State> {
    public private(set) var current: State
    private var past: [State] = []
    private var future: [State] = []
    public init(_ initial: State) { current = initial }
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public mutating func commit(_ state: State) {
        past.append(current)
        if past.count > 40 { past.removeFirst() }
        current = state; future.removeAll()
    }
    public mutating func undo() {
        guard let state = past.popLast() else { return }
        future.append(current); current = state
    }
    public mutating func redo() {
        guard let state = future.popLast() else { return }
        past.append(current); current = state
    }
}

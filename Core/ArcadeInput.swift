import Foundation

/// A sidecar clock update is not a replacement of the game. Preserve every
/// other save field and the round identity when checking coalesced ownership.
public enum ArcadeSaveOwnership {
    public static func matches(expectedSessionID: UUID?, currentSessionID: UUID?,
                               expected: ExpandedGameSave?, current: ExpandedGameSave?) -> Bool {
        guard let expectedSessionID, expectedSessionID == currentSessionID,
              let expected, var current else { return false }
        current.elapsedSeconds = expected.elapsedSeconds
        return expected == current
    }
}

/// Read one direction per swipe. Changing the angle of a finger already down
/// must not consume a second queued turn.
public struct SnakeSwipe {
    public static let minimumDistance = 12.0
    private var consumed = false
    public init() {}

    public mutating func direction(x: Double, y: Double) -> ArcadeDirection? {
        guard !consumed, x.isFinite, y.isFinite, hypot(x, y) >= Self.minimumDistance else { return nil }
        consumed = true
        if abs(x) >= abs(y) { return x >= 0 ? .right : .left }
        return y >= 0 ? .down : .up
    }
}

public enum ArcadeHeldAction: Equatable, Sendable { case left, right, softDrop }

/// Immediate first action is handled by the touch. Repeats follow elapsed time,
/// not display refresh rate; release/pause must discard the transient hold.
public struct ArcadeInputRepeat: Equatable, Sendable {
    public private(set) var held: ArcadeHeldAction?
    private var remaining = 0.0
    public init() {}
    public mutating func press(_ action: ArcadeHeldAction) -> Bool {
        guard held != action else { return false }
        held = action; remaining = action == .softDrop ? 0.07 : 0.22; return true
    }
    public mutating func release(_ action: ArcadeHeldAction) {
        if held == action { cancel() }
    }
    public mutating func cancel() { held = nil; remaining = 0 }
    public mutating func advance(_ delta: TimeInterval) -> ArcadeHeldAction? {
        guard let held, delta.isFinite, delta > 0, delta <= 0.1 else { return nil }
        remaining -= delta
        guard remaining <= 0.000_001 else { return nil }
        remaining += held == .softDrop ? 0.055 : 0.075
        // At most one action per display frame; never replay suspended time.
        remaining = max(0, remaining)
        return held
    }
}

/// One physical gesture belongs to one falling piece. It must never carry a
/// soft/hard drop onto a newly spawned piece after the previous one locks.
public struct FallingBlockDrag: Equatable, Sendable {
    public let piece: Int
    private var horizontal: Bool?
    private var previous = 0
    public init(piece: Int) { self.piece = piece }
    public mutating func change(x: Double, y: Double, unit: Double, currentPiece: Int) -> (dx: Int, down: Int) {
        guard currentPiece == piece,x.isFinite,y.isFinite,unit.isFinite,unit>0 else { return (0,0) }
        if horizontal == nil { horizontal = abs(x) >= abs(y) }
        if horizontal == true {
            let target = Int(max(-10,min(10,x/unit))), delta = target-previous
            previous = target; return (delta,0)
        }
        let target = Int(max(0,min(20,y/unit))), delta = max(0,target-previous)
        previous = max(previous,target); return (0,delta)
    }
    public func hardDrop(y: Double, predictedY: Double, unit: Double, currentPiece: Int) -> Bool {
        currentPiece == piece && horizontal == false && y.isFinite && predictedY.isFinite && unit.isFinite && unit>0 &&
            y>max(50,unit*3) && predictedY-y>max(20,unit*2)
    }
}

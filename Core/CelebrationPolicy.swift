/// Transient presentation state only. It never touches game rules or saved progress.
public struct CelebrationPolicy: Equatable, Sendable {
    private var hasObserved = false
    private var wasCompleted = false

    public init() {}

    /// Opening an already-completed save establishes a baseline, not a new win.
    public mutating func synchronize(completed: Bool) {
        hasObserved = true
        wasCompleted = completed
    }

    /// Suppressed wins are consumed, so resuming the app cannot replay them later.
    public mutating func observe(completed: Bool, isActive: Bool, reduceMotion: Bool, lowPower: Bool) -> Bool {
        let newWin = hasObserved && !wasCompleted && completed
        synchronize(completed: completed)
        return newWin && isActive && !reduceMotion && !lowPower
    }
}

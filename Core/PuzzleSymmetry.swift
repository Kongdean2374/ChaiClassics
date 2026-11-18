/// The eight rotations/reflections of a square. Transform the image before
/// deriving clues, so the clues always refer to the displayed orientation.
enum PuzzleSymmetry {
    static func sourceIndex(_ index: Int, size: Int, transform: Int) -> Int {
        var row = index / size
        var column = index % size
        if transform & 1 != 0 { row = size - 1 - row }
        if transform & 2 != 0 { column = size - 1 - column }
        if transform & 4 != 0 { swap(&row, &column) }
        return row * size + column
    }
}

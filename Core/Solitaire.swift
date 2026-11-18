import Foundation

public struct PlayingCard: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: Int
    public init(_ id: Int) { self.id = id }
    public var rank: Int { id%13+1 }
    public var suit: Int { id/13%4 } // spade, heart, club, diamond
    public var isRed: Bool { suit==1 || suit==3 }
    public var rankText: String { [1:"A",11:"J",12:"Q",13:"K"][rank] ?? String(rank) }
}
public enum SolitaireVariant: String, Codable, CaseIterable, Sendable { case klondike, spider, freecell, pyramid, tripeaks }
public enum CardPlace: Codable, Equatable, Hashable, Sendable { case column(Int), foundation(Int), freeCell(Int), waste }

public struct SolitairePosition: Codable, Equatable, Sendable {
    let stock: [PlayingCard]
    let waste: [PlayingCard]
    let columns: [[PlayingCard]]
    let foundations: [[PlayingCard]]
    let freeCells: [PlayingCard?]
    let tableau: [PlayingCard?]
    let removed: [PlayingCard]
    let faceUp: Set<Int>
}

/// Five real solitaire rules share card identities and atomic movement. Cards
/// never disappear on an illegal move; hidden cards have no selectable action.
public struct SolitaireBoard: Codable, Equatable, Sendable {
    public let variant: SolitaireVariant
    public let seed: UInt64
    public let drawCount: Int
    public let spiderSuits: Int
    public private(set) var stock: [PlayingCard]
    public private(set) var waste: [PlayingCard] = []
    public private(set) var columns: [[PlayingCard]] = []
    public private(set) var foundations: [[PlayingCard]]
    public private(set) var freeCells: [PlayingCard?] = Array(repeating:nil,count:4)
    public private(set) var tableau: [PlayingCard?] = []
    public private(set) var removed: [PlayingCard] = []
    public private(set) var faceUp: Set<Int> = []
    public private(set) var moves = 0
    public private(set) var undoHistory: [SolitairePosition] = []
    public var canUndo: Bool { !undoHistory.isEmpty }
    public init(variant: SolitaireVariant, seed: UInt64, drawCount: Int = 1, spiderSuits: Int = 1) {
        self.variant = variant; self.seed = seed; self.drawCount = [1,3].contains(drawCount) ? drawCount : 1; self.spiderSuits = [1,2,4].contains(spiderSuits) ? spiderSuits : 1
        stock = []
        var random = SeededRandom(seed:seed), deck = (0..<(variant == .spider ? 104 : 52)).map(PlayingCard.init); deck.shuffle(using:&random)
        foundations = Array(repeating:[],count:variant == .spider ? 8 : 4)
        switch variant {
        case .klondike:
            for count in 1...7 { let hand = Array(deck.suffix(count)); deck.removeLast(count); columns.append(hand); if let top = hand.last { faceUp.insert(top.id) } }
        case .spider:
            for column in 0..<10 { let count = column<4 ? 6 : 5, hand = Array(deck.suffix(count)); deck.removeLast(count); columns.append(hand); if let top = hand.last { faceUp.insert(top.id) } }
        case .freecell:
            columns = Array(repeating:[],count:8)
            for (i,card) in deck.enumerated() { columns[i%8].append(card); faceUp.insert(card.id) }; deck = []
        case .pyramid,.tripeaks:
            tableau = Array(deck.suffix(28)).map(Optional.some); deck.removeLast(28)
            if variant == .tripeaks, let card = deck.popLast() { waste.append(card); faceUp.insert(card.id) }
            for i in tableau.indices where isExposed(i) { if let card = tableau[i] { faceUp.insert(card.id) } }
        }
        stock = deck
    }
    public func effectiveSuit(_ card: PlayingCard) -> Int { variant == .spider ? (spiderSuits==1 ? 0 : spiderSuits==2 ? card.suit%2 : card.suit) : card.suit }
    public var isComplete: Bool { variant == .pyramid || variant == .tripeaks ? tableau.allSatisfy{$0==nil} : foundations.flatMap{$0}.count == (variant == .spider ? 104 : 52) }
    public var isValidSave: Bool {
        guard [1,3].contains(drawCount), [1,2,4].contains(spiderSuits), freeCells.count==4, foundations.count==(variant == .spider ? 8 : 4), (0...1_000_000).contains(moves), undoHistory.count<=30 else { return false }
        let cards = stock+waste+columns.flatMap{$0}+foundations.flatMap{$0}+freeCells.compactMap{$0}+tableau.compactMap{$0}+removed
        let count = variant == .spider ? 104 : 52
        guard cards.count==count, Set(cards.map(\.id))==Set(0..<count), faceUp.isSubset(of:Set(0..<count)), !stock.contains(where:{faceUp.contains($0.id)}) else { return false }
        switch variant {
        case .klondike: return columns.count==7 && tableau.isEmpty && removed.isEmpty && freeCells.allSatisfy{$0==nil} && foundations.allSatisfy(validFoundation)
        case .freecell: return columns.count==8 && stock.isEmpty && waste.isEmpty && tableau.isEmpty && removed.isEmpty && columns.flatMap{$0}.allSatisfy{faceUp.contains($0.id)} && foundations.allSatisfy(validFoundation)
        case .spider: return columns.count==10 && waste.isEmpty && tableau.isEmpty && removed.isEmpty && freeCells.allSatisfy{$0==nil} && foundations.allSatisfy { $0.isEmpty || $0.count==13 && isSpiderSequence($0) }
        case .pyramid,.tripeaks: return columns.isEmpty && tableau.count==28 && foundations.allSatisfy(\.isEmpty) && freeCells.allSatisfy{$0==nil}
        }
    }
    private func validFoundation(_ pile: [PlayingCard]) -> Bool { pile.enumerated().allSatisfy { $0.element.rank==$0.offset+1 && $0.element.suit==pile[0].suit } }
    private func isSpiderSequence(_ pile: [PlayingCard]) -> Bool {
        zip(pile,pile.dropFirst()).allSatisfy { $0.rank==$1.rank+1 && effectiveSuit($0)==effectiveSuit($1) }
    }
    @discardableResult public mutating func draw() -> Bool {
        guard isValidSave, !isComplete, moves<1_000_000 else { return false }
        if variant == .spider {
            guard stock.count>=10, !columns.contains(where:\.isEmpty) else { return false }
            remember()
            for i in columns.indices { let card = stock.removeLast(); columns[i].append(card); faceUp.insert(card.id) }; collectSpiderRuns()
        } else {
            guard variant != .freecell, !stock.isEmpty else { return false }
            remember()
            let count = variant == .klondike ? min(drawCount,stock.count) : 1
            for _ in 0..<count { let card = stock.removeLast(); waste.append(card); faceUp.insert(card.id) }
        }
        moves += 1; return true
    }
    @discardableResult public mutating func recycle() -> Bool {
        guard variant == .klondike, stock.isEmpty, !waste.isEmpty, !isComplete, moves<1_000_000 else { return false }
        remember()
        stock = waste.reversed(); waste = []; for card in stock { faceUp.remove(card.id) }; moves += 1; return true
    }
    public func cards(at place: CardPlace) -> [PlayingCard] {
        switch place {
        case .column(let i): return columns.indices.contains(i) ? columns[i] : []
        case .foundation(let i): return foundations.indices.contains(i) ? foundations[i] : []
        case .freeCell(let i): return freeCells.indices.contains(i) ? freeCells[i].map{[$0]} ?? [] : []
        case .waste: return waste
        }
    }
    public func movableCards(from: CardPlace, index: Int) -> [PlayingCard]? {
        guard !isComplete, variant != .pyramid, variant != .tripeaks else { return nil }
        let pile = cards(at:from)
        guard pile.indices.contains(index), faceUp.contains(pile[index].id) else { return nil }
        if variant == .spider, case .foundation = from { return nil }
        let moving = Array(pile[index...])
        guard moving.allSatisfy({faceUp.contains($0.id)}) else { return nil }
        if case .column = from {} else if moving.count != 1 || index != pile.count-1 { return nil }
        if variant == .spider { guard isSpiderSequence(moving) else { return nil } }
        else { guard zip(moving,moving.dropFirst()).allSatisfy({$0.rank==$1.rank+1 && $0.isRed != $1.isRed}) else { return nil } }
        return moving
    }
    public func canMove(from: CardPlace, index: Int, to: CardPlace) -> Bool {
        guard from != to, let moving = movableCards(from:from,index:index) else { return false }
        switch to {
        case .column(let column):
            guard columns.indices.contains(column) else { return false }
            if let top = columns[column].last {
                guard top.rank==moving[0].rank+1, variant == .spider || top.isRed != moving[0].isRed else { return false }
            } else if variant == .klondike && moving[0].rank != 13 { return false }
            if variant == .freecell {
                let empty = columns.indices.filter { columns[$0].isEmpty && $0 != column }.count
                let capacity = (freeCells.filter{$0==nil}.count+1)*(1<<empty)
                guard moving.count<=capacity else { return false }
            }
            return true
        case .foundation(let foundation):
            guard variant != .spider, foundations.indices.contains(foundation), moving.count==1 else { return false }
            let target = foundations[foundation]
            return target.isEmpty ? moving[0].rank==1 : target.last!.suit==moving[0].suit && target.last!.rank+1==moving[0].rank
        case .freeCell(let cell): return variant == .freecell && freeCells.indices.contains(cell) && freeCells[cell]==nil && moving.count==1
        case .waste: return false
        }
    }
    @discardableResult public mutating func move(from: CardPlace, index: Int, to: CardPlace) -> Bool {
        guard isValidSave, moves<1_000_000, canMove(from:from,index:index,to:to) else { return false }
        remember()
        let moving = Array(cards(at:from)[index...])
        switch from {
        case .column(let i): columns[i].removeLast(moving.count); if let top = columns[i].last { faceUp.insert(top.id) }
        case .foundation(let i): foundations[i].removeLast()
        case .freeCell(let i): freeCells[i] = nil
        case .waste: waste.removeLast()
        }
        switch to {
        case .column(let i): columns[i] += moving
        case .foundation(let i): foundations[i] += moving
        case .freeCell(let i): freeCells[i] = moving[0]
        case .waste: return false
        }
        collectSpiderRuns(); moves += 1; return true
    }
    private mutating func collectSpiderRuns() {
        guard variant == .spider else { return }
        for i in columns.indices {
            while columns[i].count>=13, let empty = foundations.firstIndex(where:\.isEmpty) {
                let run = Array(columns[i].suffix(13))
                guard run.first?.rank==13, run.last?.rank==1, run.allSatisfy({faceUp.contains($0.id)}), isSpiderSequence(run) else { break }
                columns[i].removeLast(13); foundations[empty] = run; if let top = columns[i].last { faceUp.insert(top.id) }
            }
        }
    }
    public func isExposed(_ index: Int) -> Bool {
        guard tableau.indices.contains(index), tableau[index] != nil else { return false }
        if variant == .pyramid {
            var row = 0
            while (row+1)*(row+2)/2<=index { row += 1 }
            if row==6 { return true }
            let left = index+row+1
            return tableau[left]==nil && tableau[left+1]==nil
        }
        guard variant == .tripeaks else { return false }
        let below: [Int:[Int]] = [0:[3,4],1:[5,6],2:[7,8],3:[9,10],4:[10,11],5:[12,13],6:[13,14],7:[15,16],8:[16,17],9:[18,19],10:[19,20],11:[20,21],12:[21,22],13:[22,23],14:[23,24],15:[24,25],16:[25,26],17:[26,27]]
        return below[index,default:[]].allSatisfy{tableau[$0]==nil}
    }
    /// Pyramid uses -1 for the waste top. A king is removed by itself.
    public func canRemovePyramid(_ first: Int, _ second: Int? = nil) -> Bool {
        guard variant == .pyramid, isValidSave, !isComplete, moves<1_000_000 else { return false }
        func card(_ i: Int) -> PlayingCard? { i == -1 ? waste.last : isExposed(i) ? tableau[i] : nil }
        guard let a = card(first) else { return false }
        if let second { return second != first && card(second).map { a.rank + $0.rank == 13 } == true }
        return a.rank == 13
    }
    @discardableResult public mutating func removePyramid(_ first: Int, _ second: Int? = nil) -> Bool {
        guard canRemovePyramid(first,second) else { return false }
        let indices = [first] + (second.map { [$0] } ?? [])
        remember()
        for index in indices { if index == -1 { removed.append(waste.removeLast()) } else if let value = tableau[index] { removed.append(value); tableau[index] = nil } }
        exposeTableau(); moves += 1; return true
    }
    public func canRemoveTriPeak(_ index: Int) -> Bool {
        guard variant == .tripeaks, isValidSave, !isComplete, moves<1_000_000, isExposed(index), let card = tableau[index], let top = waste.last,
              abs(card.rank-top.rank)==1 || abs(card.rank-top.rank)==12 else { return false }
        return true
    }
    @discardableResult public mutating func removeTriPeak(_ index: Int) -> Bool {
        guard canRemoveTriPeak(index), let card = tableau[index] else { return false }
        remember()
        waste.append(card); faceUp.insert(card.id); tableau[index] = nil; exposeTableau(); moves += 1; return true
    }
    private mutating func exposeTableau() { for i in tableau.indices where isExposed(i) { if let card = tableau[i] { faceUp.insert(card.id) } } }
    private mutating func remember() {
        undoHistory.append(SolitairePosition(stock:stock,waste:waste,columns:columns,foundations:foundations,freeCells:freeCells,tableau:tableau,removed:removed,faceUp:faceUp))
        if undoHistory.count>30 { undoHistory.removeFirst() }
    }
    @discardableResult public mutating func undo() -> Bool {
        let current = self
        guard moves<1_000_000, let previous = undoHistory.popLast() else { return false }
        stock = previous.stock; waste = previous.waste; columns = previous.columns; foundations = previous.foundations
        freeCells = previous.freeCells; tableau = previous.tableau; removed = previous.removed; faceUp = previous.faceUp
        moves += 1
        guard isValidSave else { self = current; return false }; return true
    }
    public var hasAvailableMove: Bool {
        if isComplete { return false }; if !stock.isEmpty && (variant != .spider || !columns.contains(where:\.isEmpty)) { return true }
        if variant == .klondike && !waste.isEmpty { return true }
        if variant == .pyramid {
            let visible = tableau.indices.filter(isExposed)+(!waste.isEmpty ? [-1] : [])
            let ranks = visible.compactMap { $0 == -1 ? waste.last?.rank : tableau[$0]?.rank }
            return ranks.contains(13) || ranks.indices.contains { a in ranks.indices.contains { b in a != b && ranks[a]+ranks[b]==13 } }
        }
        if variant == .tripeaks { return tableau.indices.contains { i in isExposed(i) && waste.last.map{abs(tableau[i]!.rank-$0.rank)==1 || abs(tableau[i]!.rank-$0.rank)==12} == true } }
        let places = columns.indices.map(CardPlace.column)+foundations.indices.map(CardPlace.foundation)+(variant == .freecell ? freeCells.indices.map(CardPlace.freeCell) : [.waste])
        for from in places { for i in cards(at:from).indices { for to in places where canMove(from:from,index:i,to:to) { return true } } }; return false
    }
}

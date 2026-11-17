import Foundation

public enum TwentyFourOperator: String, Codable, CaseIterable, Sendable {
    case add, subtract, multiply, divide
    public var symbol: String {
        switch self { case .add: return "+"; case .subtract: return "−"; case .multiply: return "×"; case .divide: return "÷" }
    }
}

/// Difficulty describes the easiest possible solution, rather than restricting player input.
public enum TwentyFourDifficulty: String, Codable, CaseIterable, Sendable {
    case easy, normal, hard
}

/// Independent subset dynamic-programming solver: it does not replay board moves.
public enum TwentyFourSolver {
    public enum Policy: Sendable { case nonnegativeWithoutDivision, nonnegativeIntegers, unrestricted }
    public static func isSolvable(_ numbers: [Int], policy: Policy = .unrestricted) -> Bool {
        guard numbers.count == 4, numbers.allSatisfy({ (1...13).contains($0) }) else { return false }
        var values = Array(repeating: Set<Rational>(), count: 16)
        for index in 0..<4 { if let n = Rational(Int64(numbers[index])) { values[1 << index].insert(n) } }
        let target = Rational(24)!
        for mask in 1..<16 where mask.nonzeroBitCount > 1 {
            var left = (mask - 1) & mask
            while left > 0 {
                let right = mask ^ left
                if right > 0 && left < right {
                    for a in values[left] {
                        for b in values[right] {
                            for operation in TwentyFourOperator.allCases {
                                if operation == .divide && policy == .nonnegativeWithoutDivision { continue }
                                let ordered: [(Rational, Rational)] = operation == .subtract || operation == .divide ? [(a, b), (b, a)] : [(a, b)]
                                for pair in ordered {
                                    guard let result = pair.0.applying(operation, to: pair.1) else { continue }
                                    if policy != .unrestricted && !result.isNonnegativeInteger { continue }
                                    if mask == 15 && result == target { return true }
                                    values[mask].insert(result)
                                }
                            }
                        }
                    }
                }
                left = (left - 1) & mask
            }
        }
        return values[15].contains(target)
    }
    public static func difficulty(of numbers: [Int]) -> TwentyFourDifficulty? {
        if isSolvable(numbers, policy: .nonnegativeWithoutDivision) { return .easy }
        if isSolvable(numbers, policy: .nonnegativeIntegers) { return .normal }
        return isSolvable(numbers) ? .hard : nil
    }
}

/// Curated by exhaustive exact-rational search over all 1...13 multisets, then independently
/// checked by the subset solver above at generation. No solution or hint is stored in the catalog.
public enum TwentyFourGenerator {
    public static func catalog(for difficulty: TwentyFourDifficulty) -> [[Int]] {
        codes(for: difficulty).map(decode)
    }
    public static var totalDistinctPuzzles: Int { easy.count + normal.count + hard.count }
    private static let classifications: [Int: TwentyFourDifficulty] = {
        var result: [Int: TwentyFourDifficulty] = [:]
        for difficulty in TwentyFourDifficulty.allCases {
            for code in codes(for: difficulty) { result[code] = difficulty }
        }
        return result
    }()
    public static func catalogDifficulty(of numbers: [Int]) -> TwentyFourDifficulty? {
        guard numbers.count == 4, numbers.allSatisfy({ (1...13).contains($0) }) else { return nil }
        let code = numbers.sorted().enumerated().reduce(0) { $0 | ($1.element << ($1.offset * 4)) }
        return classifications[code]
    }
    public static func numbers(difficulty: TwentyFourDifficulty, seed: UInt64, index: Int = 0) -> [Int] {
        let codes = codes(for: difficulty)
        var rng = SeededRandom(seed: seed)
        let offset = Int(rng.next() % UInt64(codes.count))
        var stride = Int(rng.next() % UInt64(codes.count - 1)) + 1
        while gcd(stride, codes.count) != 1 { stride = stride % (codes.count - 1) + 1 }
        let position = (offset + (max(0, index) % codes.count) * stride) % codes.count
        let policy: TwentyFourSolver.Policy
        switch difficulty {
        case .easy: policy = .nonnegativeWithoutDivision
        case .normal: policy = .nonnegativeIntegers
        case .hard: policy = .unrestricted
        }
        // Bounded fallback protects generation if a future catalog edit introduces an invalid row.
        for delta in 0..<codes.count {
            let puzzle = decode(codes[(position + delta) % codes.count])
            if TwentyFourSolver.isSolvable(puzzle, policy: policy) {
                var shuffled = puzzle
                shuffled.shuffle(using: &rng)
                return shuffled
            }
        }
        switch difficulty { case .easy: return [1, 2, 3, 4]; case .normal: return [1, 1, 6, 8]; case .hard: return [3, 3, 8, 8] }
    }
    private static func decode(_ code: Int) -> [Int] { (0..<4).map { (code >> ($0 * 4)) & 15 } }
    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }
    private static func codes(for difficulty: TwentyFourDifficulty) -> [Int] {
        switch difficulty { case .easy: return easy; case .normal: return normal; case .hard: return hard }
    }
    private static let easy: [Int] = [
        33041, 45329, 49425, 53521, 25105, 29201, 33297, 37393, 41489, 45585, 49681, 53777, 17169, 21265, 25361, 29457, 33553, 37649, 41745, 45841,
        49937, 54033, 17425, 21521, 25617, 29713, 33809, 37905, 42001, 50193, 21777, 25873, 29969, 34065, 26129, 38417, 50705, 42769, 34833, 55569,
        51729, 55825, 47889, 51985, 56081, 52241, 56337, 56593, 16929, 21025, 25121, 29217, 33313, 37409, 41505, 45601, 49697, 53793, 13089, 17185,
        21281, 25377, 29473, 33569, 37665, 41761, 45857, 49953, 54049, 17441, 21537, 25633, 29729, 33825, 37921, 42017, 46113, 50209, 54305, 21793,
        25889, 29985, 34081, 38177, 42273, 50465, 54561, 26145, 30241, 34337, 38433, 42529, 46625, 50721, 54817, 34593, 38689, 42785, 46881, 50977,
        34849, 38945, 43041, 55329, 47393, 51489, 55585, 47649, 51745, 55841, 47905, 52001, 56097, 52257, 56353, 56609, 13105, 17201, 21297, 25393,
        29489, 33585, 37681, 41777, 45873, 49969, 17457, 21553, 29745, 33841, 37937, 42033, 46129, 50225, 54321, 25905, 30001, 34097, 38193, 42289,
        46385, 50481, 54577, 26161, 30257, 34353, 38449, 42545, 46641, 50737, 54833, 30513, 34609, 42801, 55089, 34865, 47153, 51249, 55345, 43313,
        47409, 51505, 55601, 43569, 47665, 51761, 47921, 52017, 52273, 56369, 56625, 17473, 21569, 25665, 29761, 33857, 37953, 42049, 46145, 50241,
        21825, 30017, 34113, 38209, 42305, 46401, 50497, 54593, 26177, 30273, 34369, 38465, 42561, 46657, 50753, 54849, 30529, 34625, 38721, 46913,
        51009, 55105, 34881, 38977, 47169, 51265, 55361, 43329, 47425, 51521, 55617, 43585, 47681, 51777, 52289, 25937, 38225, 42321, 46417, 54609,
        26193, 30289, 34385, 38481, 42577, 46673, 50769, 54865, 34641, 38737, 42833, 46929, 51025, 55121, 34897, 38993, 43089, 47185, 51281, 55377,
        39249, 43345, 47441, 51537, 55633, 43601, 26209, 38497, 42593, 46689, 50785, 54881, 38753, 42849, 46945, 51041, 34913, 39009, 43105, 47201,
        51297, 55393, 39265, 43361, 51553, 55649, 55905, 38769, 42865, 46961, 34929, 39025, 43121, 47217, 51313, 39281, 43377, 47473, 51569, 55665,
        51825, 55921, 34945, 39041, 43137, 47233, 51329, 47489, 51585, 55681, 47745, 51841, 55937, 52097, 56193, 51601, 51857, 55953, 48017, 52113,
        56209, 52369, 52129, 52385, 56481, 56241, 52401, 56497, 56753, 56513, 12834, 16930, 21026, 29218, 33314, 37410, 41506, 45602, 49698, 53794,
        13090, 17186, 21282, 25378, 29474, 33570, 37666, 41762, 45858, 49954, 54050, 17442, 21538, 25634, 29730, 33826, 37922, 42018, 46114, 50210,
        54306, 21794, 25890, 29986, 34082, 38178, 42274, 46370, 50466, 26146, 30242, 34338, 38434, 42530, 46626, 50722, 54818, 30498, 34594, 50978,
        55074, 34850, 38946, 43042, 51234, 43298, 47394, 51490, 43554, 47650, 56098, 52258, 13106, 21298, 25394, 29490, 33586, 37682, 41778, 45874,
        49970, 54066, 17458, 21554, 25650, 29746, 33842, 37938, 42034, 46130, 50226, 54322, 21810, 25906, 30002, 34098, 38194, 42290, 46386, 54578,
        26162, 30258, 34354, 38450, 42546, 50738, 54834, 30514, 34610, 38706, 42802, 46898, 50994, 55090, 34866, 38962, 43058, 47154, 51250, 55346,
        39218, 43314, 51506, 55602, 43570, 51762, 55858, 47922, 52018, 56114, 52274, 56370, 56626, 17474, 21570, 25666, 29762, 33858, 37954, 42050,
        50242, 21826, 25922, 30018, 34114, 38210, 42306, 46402, 50498, 54594, 26178, 30274, 34370, 38466, 42562, 46658, 50754, 54850, 30530, 34626,
        38722, 42818, 46914, 51010, 34882, 38978, 43074, 47170, 51266, 39234, 43330, 51522, 55618, 47682, 51778, 55874, 47938, 52034, 52290, 56642,
        30034, 38226, 46418, 50514, 54610, 26194, 30290, 34386, 42578, 46674, 50770, 54866, 30546, 34642, 38738, 42834, 46930, 55122, 34898, 38994,
        43090, 47186, 51282, 55378, 43346, 47442, 51538, 47698, 51794, 55890, 52050, 52306, 56402, 26210, 30306, 34402, 38498, 42594, 50786, 34658,
        38754, 42850, 46946, 51042, 55138, 34914, 39010, 43106, 47202, 51298, 55394, 39266, 43362, 47458, 51554, 43618, 47714, 51810, 55906, 56162,
        52322, 34674, 46962, 51058, 34930, 39026, 47218, 51314, 55410, 43378, 47474, 55666, 43634, 47730, 52082, 52338, 56434, 34946, 39042, 43138,
        51330, 55426, 39298, 43394, 47490, 51586, 55682, 43650, 47746, 51842, 55938, 52098, 52354, 56450, 51602, 47762, 51858, 55954, 48018, 56210,
        56466, 51874, 55970, 48034, 52130, 56226, 56482, 52146, 56242, 52402, 56498, 56754, 52418, 56514, 56770, 13107, 17203, 21299, 25395, 29491,
        33587, 41779, 45875, 49971, 17459, 21555, 25651, 29747, 33843, 37939, 46131, 50227, 54323, 25907, 30003, 38195, 42291, 50483, 54579, 30259,
        34355, 38451, 42547, 46643, 50739, 54835, 34611, 38707, 46899, 50995, 55091, 38963, 43059, 51251, 55347, 39219, 43315, 51507, 55603, 52019,
        56115, 52275, 56371, 17475, 21571, 25667, 29763, 33859, 37955, 42051, 46147, 54339, 21827, 25923, 30019, 34115, 38211, 42307, 46403, 50499,
        54595, 26179, 34371, 38467, 42563, 46659, 50755, 30531, 34627, 38723, 42819, 46915, 38979, 43075, 47171, 51267, 39235, 47427, 51523, 55619,
        43587, 51779, 55875, 52035, 56131, 52291, 56387, 25939, 30035, 34131, 46419, 26195, 30291, 34387, 38483, 42579, 46675, 50771, 54867, 34643,
        38739, 42835, 46931, 51027, 34899, 38995, 47187, 51283, 55379, 39251, 43347, 51539, 55635, 47699, 51795, 55891, 47955, 52307, 56403, 56659,
        26211, 30307, 34403, 38499, 42595, 50787, 54883, 30563, 34659, 38755, 51043, 55139, 34915, 39011, 43107, 51299, 55395, 39267, 43363, 47459,
        51555, 55651, 47715, 51811, 52067, 56163, 52323, 56419, 30579, 34675, 42867, 55155, 34931, 39027, 47219, 51315, 55411, 39283, 43379, 47475,
        51571, 55667, 43635, 47731, 55923, 52083, 52339, 56435, 34947, 39043, 47235, 39299, 43395, 47491, 51587, 55683, 43651, 47747, 48003, 52099,
        52355, 56451, 56707, 39315, 43411, 47507, 51603, 55699, 47763, 51859, 55955, 52115, 56211, 56467, 51875, 52131, 56227, 52403, 56515, 17476,
        25668, 29764, 33860, 37956, 42052, 46148, 50244, 21828, 25924, 30020, 34116, 42308, 46404, 50500, 54596, 34372, 38468, 42564, 46660, 50756,
        54852, 34628, 38724, 42820, 51012, 55108, 34884, 38980, 43076, 47172, 51268, 55364, 47428, 51524, 51780, 55876, 56132, 52292, 56388, 21844,
        25940, 38228, 42324, 26196, 30292, 34388, 38484, 42580, 54868, 30548, 34644, 38740, 42836, 46932, 51028, 55124, 38996, 47188, 51284, 55380,
        43348, 51540, 55636, 47700, 55892, 47956, 52052, 56148, 52308, 56404, 26212, 30308, 34404, 38500, 50788, 30564, 34660, 42852, 34916, 39012,
        43108, 51300, 55396, 39268, 43364, 51556, 55652, 43620, 47716, 51812, 47972, 52068, 52324, 56420, 56676, 34676, 46964, 34932, 39028, 47220,
        51316, 55412, 43380, 47476, 51572, 55668, 47732, 51828, 52084, 56180, 52340, 56436, 34948, 39044, 43140, 51332, 43396, 47492, 51588, 55684,
        43652, 47748, 51844, 52100, 56196, 56452, 43412, 51604, 47764, 55956, 48020, 52116, 52372, 47780, 51876, 56228, 52388, 56484, 56500, 52420,
        25941, 38229, 26197, 30293, 34389, 46677, 30549, 34645, 38997, 47189, 51285, 55381, 43349, 47445, 47701, 52053, 56149, 52309, 56405, 30309,
        34405, 38501, 42597, 50789, 34661, 38757, 51045, 55141, 34917, 39013, 43109, 39269, 43365, 51557, 55653, 47717, 55909, 52069, 56165, 52325,
        56421, 38773, 42869, 34933, 39029, 43125, 43381, 47477, 55669, 47733, 51829, 55925, 47989, 56181, 52341, 56693, 34949, 39045, 43141, 55429,
        47493, 51589, 55685, 47749, 51845, 52101, 56197, 52357, 47509, 51605, 43669, 47765, 55957, 56213, 52373, 56469, 56485, 56741, 26214, 34406,
        38502, 42598, 46694, 38758, 42854, 46950, 51046, 39014, 43110, 47206, 51302, 55398, 43366, 47462, 51558, 55654, 51814, 55910, 56166, 52326,
        42870, 46966, 43126, 47222, 39286, 51574, 43638, 51830, 55926, 47990, 52086, 56182, 52342, 56438, 34950, 39046, 43142, 47238, 51334, 43398,
        51590, 55686, 47750, 51846, 55942, 48006, 56198, 52358, 56710, 47510, 51606, 47766, 51862, 52118, 56214, 52374, 56470, 43686, 55974, 52390,
        56502, 47223, 43383, 52087, 56183, 52343, 56439, 39047, 43143, 47239, 51335, 55687, 43655, 55943, 52103, 56199, 52359, 56455, 55703, 47767,
        51863, 48023, 52119, 52375, 56727, 47783, 51879, 56231, 52391, 43144, 47240, 51336, 55432, 47496, 51592, 55688, 51848, 55944, 56200, 52360,
        55960, 48024, 52120, 56216, 52376, 56472, 51880, 48040, 52392, 56744, 52408, 52121, 56217, 52377, 56473, 55977, 52137, 56233, 52393, 56489,
        48057, 52409, 56761, 52425, 56234, 52394, 52154, 56250, 52410, 56506, 52426, 56522, 56778, 56251, 52411, 56507, 52427, 56523, 56779, 56795,
        52428, 56524, 56780
    ]
    private static let normal: [Int] = [
        34321, 30497, 38705, 50993, 38961, 43057, 39217, 50513, 47697, 51793, 55889, 47953, 52049, 52305, 51809, 52065, 56161, 52321, 56417, 51057,
        52337, 56433, 56689, 51873, 52145, 52417, 56769, 42786, 55842, 52002, 56354, 46642, 46146, 54338, 55362, 34130, 38482, 43602, 46690, 54882,
        52066, 56418, 55154, 51826, 47234, 48002, 56706, 47506, 55698, 43666, 56722, 47778, 48050, 56786, 37683, 21811, 26163, 47411, 55859, 50243,
        54851, 51011, 55363, 38227, 50515, 55123, 43603, 52051, 46691, 42851, 43619, 47971, 56675, 38771, 51059, 47987, 56691, 43139, 51331, 51843,
        43667, 48019, 52371, 56723, 52147, 52419, 56771, 21572, 43588, 52036, 30036, 34132, 46676, 50772, 34900, 43092, 39252, 43604, 51796, 56660,
        42596, 38756, 51044, 30580, 43124, 39284, 43636, 47988, 56692, 47236, 55428, 39300, 48004, 52356, 56708, 51860, 52132, 21845, 50517, 42837,
        34901, 43093, 39253, 43605, 55893, 47957, 56661, 26213, 30565, 51301, 55397, 47461, 43621, 51813, 47973, 56677, 51573, 43637, 47781, 51877,
        55973, 48037, 52405, 50790, 34918, 52070, 56422, 39030, 51318, 39302, 47494, 52102, 43414, 52134, 56486, 52150, 52406, 52422, 56518, 56774,
        51063, 55927, 55431, 43399, 51591, 47751, 56487, 56519, 52104, 56456, 51608, 51864, 56488, 51609, 55961, 56505, 51882, 55978, 52138, 56490,
        56794, 52155, 56796
    ]
    private static let hard: [Int] = [
        25649, 25921, 21841, 34401, 52353, 47906, 56610, 50482, 43586, 42322, 42866, 30515, 34867, 30532, 46933, 46965
    ]
}

public struct TwentyFourMove: Codable, Equatable, Sendable {
    public let firstID: Int
    public let secondID: Int
    public let operation: TwentyFourOperator
    public init(firstID: Int, secondID: Int, operation: TwentyFourOperator) {
        self.firstID = firstID; self.secondID = secondID; self.operation = operation
    }
}

public struct TwentyFourCard: Equatable, Identifiable, Sendable {
    public let id: Int
    public let value: Rational
    public let expression: String
    /// Bitset of the four original physical cards represented by this expression.
    public let sourceMask: Int
}

/// Only source numbers and a maximum of three moves are persisted. Values, parentheses and
/// card identities are reconstructed and validated rather than trusting saved formula strings.
public struct TwentyFourBoard: Codable, Equatable, Sendable {
    public enum BoardError: Error { case invalidNumbers, unsolvable }
    public let difficulty: TwentyFourDifficulty
    public let seed: UInt64
    public private(set) var numbers: [Int]
    public private(set) var history: [TwentyFourMove] = []
    public private(set) var puzzleIndex = 0
    public private(set) var solvedCount = 0
    public private(set) var recordedSuccess = false
    public var elapsedSeconds = 0

    public init(difficulty: TwentyFourDifficulty = .easy, seed: UInt64 = UInt64.random(in: .min ... .max)) {
        self.difficulty = difficulty; self.seed = seed
        numbers = TwentyFourGenerator.numbers(difficulty: difficulty, seed: seed)
    }
    /// Deterministic real puzzle fixture; unsolvable/invalid input is rejected.
    public init(numbers: [Int], seed: UInt64 = UInt64.random(in: .min ... .max)) throws {
        guard numbers.count == 4, numbers.allSatisfy({ (1...13).contains($0) }) else { throw BoardError.invalidNumbers }
        guard let difficulty = TwentyFourSolver.difficulty(of: numbers) else { throw BoardError.unsolvable }
        self.numbers = numbers; self.difficulty = difficulty; self.seed = seed
    }
    public var cards: [TwentyFourCard] { reconstruct() ?? [] }
    public var isComplete: Bool {
        let active = cards
        return active.count == 1 && active[0].sourceMask == 15 && active[0].value == Rational(24)
    }
    public var isEnded: Bool { cards.count == 1 }
    public var moves: Int { history.count }
    public var canUndo: Bool { !history.isEmpty }
    public func canCombine(firstID: Int, secondID: Int, operation: TwentyFourOperator) -> Bool {
        guard isValidSave, firstID != secondID, !isEnded,
              let first = cards.first(where: { $0.id == firstID }),
              let second = cards.first(where: { $0.id == secondID }) else { return false }
        return first.value.applying(operation, to: second.value) != nil
    }
    @discardableResult public mutating func combine(firstID: Int, secondID: Int, operation: TwentyFourOperator) -> Bool {
        guard history.count < 3, canCombine(firstID: firstID, secondID: secondID, operation: operation) else { return false }
        history.append(TwentyFourMove(firstID: firstID, secondID: secondID, operation: operation))
        if isComplete && !recordedSuccess {
            solvedCount += 1; recordedSuccess = true
        }
        return true
    }
    @discardableResult public mutating func undo() -> Bool {
        guard isValidSave, !history.isEmpty else { return false }
        history.removeLast(); return true
    }
    public mutating func reset() {
        guard isValidSave else { return }
        history = []; elapsedSeconds = 0
    }
    public mutating func nextPuzzle() {
        guard isValidSave, puzzleIndex < 1_000_000_000 else { return }
        puzzleIndex += 1
        numbers = TwentyFourGenerator.numbers(difficulty: difficulty, seed: seed, index: puzzleIndex)
        history = []; elapsedSeconds = 0; recordedSuccess = false
    }
    private func reconstruct() -> [TwentyFourCard]? {
        guard numbers.count == 4, numbers.allSatisfy({ (1...13).contains($0) }), history.count <= 3 else { return nil }
        var active = numbers.enumerated().map { index, number in
            TwentyFourCard(id: index, value: Rational(Int64(number))!, expression: String(number), sourceMask: 1 << index)
        }
        for (index, move) in history.enumerated() {
            guard move.firstID != move.secondID,
                  let first = active.first(where: { $0.id == move.firstID }),
                  let second = active.first(where: { $0.id == move.secondID }),
                  first.sourceMask & second.sourceMask == 0,
                  let result = first.value.applying(move.operation, to: second.value) else { return nil }
            active.removeAll { $0.id == move.firstID || $0.id == move.secondID }
            active.append(TwentyFourCard(id: 4 + index, value: result,
                                        expression: "(\(first.expression) \(move.operation.symbol) \(second.expression))",
                                        sourceMask: first.sourceMask | second.sourceMask))
        }
        return active
    }
    public var isValidSave: Bool {
        guard (0...315_360_000).contains(elapsedSeconds), (0...1_000_000_000).contains(puzzleIndex),
              solvedCount >= 0, solvedCount <= puzzleIndex + 1,
              !recordedSuccess || solvedCount > 0, !isComplete || recordedSuccess,
              reconstruct() != nil else { return false }
        // Cached catalog membership detects altered difficulty/source data without solving on timer saves.
        return TwentyFourGenerator.catalogDifficulty(of: numbers) == difficulty
    }
}

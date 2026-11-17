import Foundation

/// A normalized exact fraction. Every arithmetic operation reports overflow by returning nil.
public struct Rational: Hashable, Codable, Sendable, CustomStringConvertible {
    public let numerator: Int64
    public let denominator: Int64

    public init?(_ numerator: Int64, _ denominator: Int64 = 1) {
        guard denominator != 0 else { return nil }
        let divisor = Self.gcd(numerator.magnitude, denominator.magnitude)
        let n = numerator.magnitude / divisor
        let d = denominator.magnitude / divisor
        guard d <= UInt64(Int64.max) else { return nil }
        let negative = (numerator < 0) != (denominator < 0)
        if negative {
            guard n <= UInt64(Int64.max) + 1 else { return nil }
            self.numerator = n == UInt64(Int64.max) + 1 ? .min : -Int64(n)
        } else {
            guard n <= UInt64(Int64.max) else { return nil }
            self.numerator = Int64(n)
        }
        self.denominator = Int64(d)
    }
    private enum CodingKeys: String, CodingKey { case numerator, denominator }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let n = try c.decode(Int64.self, forKey: .numerator)
        let d = try c.decode(Int64.self, forKey: .denominator)
        guard let value = Rational(n, d), value.numerator == n, value.denominator == d else {
            throw DecodingError.dataCorruptedError(forKey: .denominator, in: c, debugDescription: "Invalid normalized fraction")
        }
        self = value
    }
    private static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return max(1, x)
    }
    public var description: String { denominator == 1 ? String(numerator) : "\(numerator)/\(denominator)" }
    public var isInteger: Bool { denominator == 1 }
    public var isZero: Bool { numerator == 0 }
    public var isNonnegativeInteger: Bool { numerator >= 0 && denominator == 1 }
    public func applying(_ operation: TwentyFourOperator, to other: Rational) -> Rational? {
        switch operation {
        case .add, .subtract:
            let common = Int64(Self.gcd(UInt64(denominator), UInt64(other.denominator)))
            let (left, lOverflow) = numerator.multipliedReportingOverflow(by: other.denominator / common)
            let (right, rOverflow) = other.numerator.multipliedReportingOverflow(by: denominator / common)
            let (sum, sOverflow) = operation == .add ? left.addingReportingOverflow(right) : left.subtractingReportingOverflow(right)
            let (bottom, bOverflow) = (denominator / common).multipliedReportingOverflow(by: other.denominator)
            guard !lOverflow, !rOverflow, !sOverflow, !bOverflow else { return nil }
            return Rational(sum, bottom)
        case .multiply:
            let cross1 = Int64(Self.gcd(numerator.magnitude, UInt64(other.denominator)))
            let cross2 = Int64(Self.gcd(other.numerator.magnitude, UInt64(denominator)))
            let (top, tOverflow) = (numerator / cross1).multipliedReportingOverflow(by: other.numerator / cross2)
            let (bottom, bOverflow) = (denominator / cross2).multipliedReportingOverflow(by: other.denominator / cross1)
            guard !tOverflow, !bOverflow else { return nil }
            return Rational(top, bottom)
        case .divide:
            guard !other.isZero, let inverse = Rational(other.denominator, other.numerator) else { return nil }
            return applying(.multiply, to: inverse)
        }
    }
}

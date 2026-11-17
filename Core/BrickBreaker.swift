import Foundation

public struct BrickBreakerBoard: Codable, Equatable, Sendable {
    public let seed: UInt64
    public private(set) var bricks: [Int]
    public private(set) var ballX = 0.5
    public private(set) var ballY = 0.83
    public private(set) var velocityX = 0.23
    public private(set) var velocityY = -0.43
    public private(set) var paddle = 0.5
    public private(set) var lives = 3
    public private(set) var score = 0
    public private(set) var launched = false
    public var isComplete: Bool { bricks.allSatisfy{$0==0} }
    public var hasLost: Bool { lives==0 }
    public init(seed: UInt64, hard: Bool = false) {
        self.seed = seed; var random = SeededRandom(seed:seed)
        bricks = (0..<40).map { _ in hard ? Int.random(in:1...3,using:&random) : 1 }
    }
    public var isValidSave: Bool {
        bricks.count==40 && bricks.allSatisfy{(0...3).contains($0)} && [ballX,ballY,velocityX,velocityY,paddle].allSatisfy(\.isFinite) &&
        (-0.05...1.05).contains(ballX) && (-0.05...1.05).contains(ballY) && (0.12...0.88).contains(paddle) &&
        abs(velocityX)<=2 && abs(velocityY)<=2 && (0...3).contains(lives) && (0...10_000).contains(score)
    }
    @discardableResult public mutating func movePaddle(to value: Double) -> Bool {
        guard value.isFinite, !hasLost, !isComplete else { return false }
        let next = min(0.88,max(0.12,value)); guard next != paddle else { return false }; paddle = next
        if !launched { ballX = paddle }; return true
    }
    @discardableResult public mutating func launch() -> Bool {
        guard !launched, !hasLost, !isComplete else { return false }; launched = true; return true
    }
    /// Bounded substeps prevent tunneling through a thin brick or paddle, even
    /// after a dropped display frame. Background time must never be integrated.
    @discardableResult public mutating func advance(_ seconds: Double) -> Bool {
        guard isValidSave, launched, !hasLost, !isComplete, seconds.isFinite, seconds>0, seconds<=0.1 else { return false }
        let count = max(1,Int(ceil(seconds*240))), dt = seconds/Double(count), radius = 0.012
        for _ in 0..<count {
            let beforeX = ballX, beforeY = ballY
            ballX += velocityX*dt; ballY += velocityY*dt
            if ballX<radius { ballX = radius; velocityX = abs(velocityX) }
            if ballX>1-radius { ballX = 1-radius; velocityX = -abs(velocityX) }
            if ballY<radius { ballY = radius; velocityY = abs(velocityY) }
            if velocityY>0, beforeY+radius<=0.9, ballY+radius>=0.9, abs(ballX-paddle)<=0.12+radius {
                ballY = 0.9-radius; let offset = max(-1,min(1,(ballX-paddle)/0.12))
                velocityX = offset*0.48; velocityY = -sqrt(max(0.1,0.55*0.55-velocityX*velocityX))
            }
            var hit = false
            for i in bricks.indices where bricks[i]>0 {
                let left = 0.02+Double(i%8)*0.12, top = 0.09+Double(i/8)*0.055, right = left+0.112, bottom = top+0.042
                if ballX+radius>=left && ballX-radius<=right && ballY+radius>=top && ballY-radius<=bottom {
                    bricks[i] -= 1; score += 10
                    if beforeX+radius<=left || beforeX-radius>=right { velocityX = -velocityX; ballX = beforeX }
                    else { velocityY = -velocityY; ballY = beforeY }; hit = true; break
                }
            }
            if ballY>1+radius {
                lives -= 1; launched = false; ballX = paddle; ballY = 0.83; velocityX = 0.23; velocityY = -0.43; break
            }
            if hit && isComplete { break }
        }; return true
    }
}

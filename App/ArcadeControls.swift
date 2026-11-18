import SwiftUI
import ChaiCore

enum ArcadePalette {
    static let blocks: [Color] = [.cyan,.yellow,.purple,.green,.red,.blue,.orange]
}

/// Turn as soon as the swipe crosses the threshold. A gesture can queue only
/// one turn, including when the finger curves before it lifts.
struct SnakeSwipeControls: ViewModifier {
    let enabled: Bool
    let turn: (ArcadeDirection) -> Void
    @GestureState private var tracking = false
    @State private var swipe = SnakeSwipe()

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(swipeGesture, including: enabled ? .all : .none)
            .onChange(of: tracking) { _, tracking in if !tracking { endSwipe() } }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: CGFloat(SnakeSwipe.minimumDistance), coordinateSpace: .global)
            .updating($tracking) { _, tracking, _ in tracking = true }
            .onChanged { value in
                guard enabled, !swipe.consumed else { return }
                if let direction = swipe.direction(x: Double(value.translation.width), y: Double(value.translation.height)) {
                    turn(direction)
                }
            }
            .onEnded { _ in endSwipe() }
    }

    private func endSwipe() {
        if swipe.consumed { swipe.finish() }
    }
}

/// Touch-down acts once; holding repeats through the display clock. GestureState
/// also cancels the hold when a system gesture interrupts the finger.
struct ArcadeRepeatButton: View {
    let title: String
    let symbol: String
    let identifier: String
    let enabled: Bool
    let begin: () -> Void
    let end: () -> Void
    let accessibleTap: () -> Void
    @GestureState private var pressed = false
    @State private var tracking = false
    var body: some View {
        Image(systemName:symbol).font(.title3.weight(.semibold))
            .frame(maxWidth:.infinity,minHeight:48)
            .background(pressed ? GameMaterial.gold.opacity(0.28) : Color.secondary.opacity(0.12),in:RoundedRectangle(cornerRadius:12))
            .overlay { RoundedRectangle(cornerRadius:12).strokeBorder(GameMaterial.gold.opacity(pressed ? 0.8 : 0.18)) }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).updating($pressed) { _,value,_ in value = true }
                .onChanged { _ in guard enabled,!tracking else { return }; tracking = true; begin() }
                .onEnded { _ in release() })
            .onChange(of:pressed) { _,value in if !value { release() } }
            .onChange(of:enabled) { _,value in if !value { release() } }
            .onDisappear { release() }
            .accessibilityElement(children:.ignore).accessibilityAddTraits(.isButton)
            .accessibilityLabel(title).accessibilityIdentifier(identifier)
            .accessibilityAction { if enabled { accessibleTap() } }
            .disabled(!enabled).allowsHitTesting(enabled).opacity(enabled ? 1 : 0.4)
    }
    private func release() { if tracking { tracking = false; end() } }
}

struct FallingPiecePreview: View {
    let kind: Int?
    let title: String
    let pieceName: String
    var body: some View {
        VStack(spacing:3) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            Canvas { context,size in
                guard let kind else { return }
                let points = FallingBlocksBoard.shape(kind,rotation:0)
                let minX = points.map(\.x).min() ?? 0, minY = points.map(\.y).min() ?? 0
                let columns = (points.map(\.x).max() ?? 0)-minX+1, rows = (points.map(\.y).max() ?? 0)-minY+1
                let unit = min(size.width/4,size.height/2)
                for p in points {
                    let rect = CGRect(x:(size.width-CGFloat(columns)*unit)/2+CGFloat(p.x-minX)*unit+1,
                                      y:(size.height-CGFloat(rows)*unit)/2+CGFloat(p.y-minY)*unit+1,
                                      width:unit-2,height:unit-2)
                    context.fill(Path(roundedRect:rect,cornerRadius:2),with:.color(ArcadePalette.blocks[kind]))
                }
            }.frame(width:64,height:30)
                .overlay { if kind == nil { Text("—").foregroundStyle(.secondary) } }
        }.padding(.vertical,5).frame(width:74)
            .background(.thinMaterial,in:RoundedRectangle(cornerRadius:10))
            .accessibilityElement(children:.ignore).accessibilityLabel(title).accessibilityValue(pieceName)
    }
}

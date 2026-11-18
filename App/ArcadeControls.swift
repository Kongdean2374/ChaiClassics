import SwiftUI
import ChaiCore

enum ArcadePalette {
    static let blocks: [Color] = [.cyan,.yellow,.purple,.green,.red,.blue,.orange]
}

/// A cardinal stick, not an eight-way controller. The knob tracks the finger
/// directly, while four native accessible buttons remain available for taps.
struct CardinalJoystick: View {
    let enabled: Bool
    let direction: ArcadeDirection
    let title: String
    let hint: String
    let label: (ArcadeDirection) -> String
    let turn: (ArcadeDirection) -> Void
    @GestureState private var offset = CGSize.zero
    @State private var lastInput: ArcadeDirection?

    var body: some View {
        ZStack {
            Circle().fill(GameMaterial.teal.gradient).frame(width:112,height:112)
                .overlay { Circle().strokeBorder(GameMaterial.gold.opacity(0.8),lineWidth:1.5) }
                .overlay {
                    Image(systemName:"plus").font(.system(size:72,weight:.ultraLight))
                        .foregroundStyle(GameMaterial.ivory.opacity(0.15))
                }
                .overlay {
                    Circle().fill(GameMaterial.gold.gradient).frame(width:38,height:38)
                        .overlay { Circle().strokeBorder(GameMaterial.ivory.opacity(0.7),lineWidth:1) }
                        .shadow(color:.black.opacity(0.25),radius:3,y:2).offset(offset)
                        .allowsHitTesting(false)
                }
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance:0).updating($offset) { value,state,_ in
                    let x = value.location.x-56, y = value.location.y-56
                    let scale = min(1,32/max(1,hypot(x,y)))
                    state = CGSize(width:x*scale,height:y*scale)
                }.onChanged { value in
                    guard enabled else { return }
                    let input = CardinalStick.direction(x:Double((value.location.x-56)/32),y:Double((value.location.y-56)/32))
                    if input != lastInput { lastInput = input; if let input { turn(input) } }
                }.onEnded { _ in lastInput = nil })
                .accessibilityElement(children:.ignore).accessibilityLabel(title)
                .accessibilityHint(hint).accessibilityValue(label(direction))
                .accessibilityIdentifier("snake.joystick")
                .accessibilityAction(named:label(.up)) { if enabled { turn(.up) } }
                .accessibilityAction(named:label(.right)) { if enabled { turn(.right) } }
                .accessibilityAction(named:label(.down)) { if enabled { turn(.down) } }
                .accessibilityAction(named:label(.left)) { if enabled { turn(.left) } }
            ForEach(ArcadeDirection.allCases,id:\.self) { input in
                Button { if enabled { turn(input) } } label: {
                    Image(systemName:["chevron.up","chevron.right","chevron.down","chevron.left"][input.rawValue])
                        .font(.system(size:18,weight:.bold)).foregroundStyle(input == direction ? GameMaterial.gold : GameMaterial.ivory)
                        .frame(width:44,height:44).background(GameMaterial.navy.opacity(0.65),in:Circle())
                }.buttonStyle(.plain).offset(x:CGFloat(input.dx)*59,y:CGFloat(input.dy)*59)
                    .accessibilityLabel(label(input)).accessibilityIdentifier("snake.direction.\(input.rawValue)")
            }
        }.frame(width:162,height:162).disabled(!enabled).opacity(enabled ? 1 : 0.5)
            .transaction { $0.animation = nil }
            .onChange(of:offset) { _,value in if value == .zero { lastInput = nil } }
            .onChange(of:enabled) { _,value in if !value { lastInput = nil } }
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

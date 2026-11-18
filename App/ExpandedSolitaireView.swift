import SwiftUI
import ChaiCore

private struct CardSelection: Equatable { let place: CardPlace; let index: Int }
private struct SolitaireLiftedCards {
    let sessionID: UUID
    let intent: SolitaireDragIntent
    let origin: CGPoint
    let frame: CGRect
}

private final class SolitaireFingerPosition: ObservableObject {
    @Published var translation: CGSize = .zero
}

struct ExpandedSolitaireView: View {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    @State private var selected: CardSelection?
    @State private var pyramidSelection: Int?
    @State private var lifted: SolitaireLiftedCards?
    @StateObject private var finger = SolitaireFingerPosition()
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered: SolitaireDropTarget?
    @State private var moveHelpKey: String?
    @State private var viewportWidth: CGFloat = 320
    private var board: SolitaireBoard? { if case .solitaire(let board) = model.expandedGames[game]?.state { return board }; return nil }
    private var active: Bool { isEnabled && model.sessionIsPlaying(game) }
    var body: some View {
        ScrollView {
            if let board {
                VStack(spacing:18) {
                    HStack {
                        GameArtwork(game:game,size:44)
                        Text(model.gameTitle(game)).font(.headline); Spacer()
                        Text(model.t("expanded.moves",board.moves)).font(.caption).monospacedDigit()
                    }
                    if board.variant == .spider,!board.stock.isEmpty,board.columns.contains(where:\.isEmpty) {
                        Text(model.t("expanded.spider.emptyColumn")).font(.caption).foregroundStyle(.secondary)
                    }
                    Button { if mutate({$0.undo()}) { selected = nil; pyramidSelection = nil } } label: {
                        Label(model.t("expanded.undo"),systemImage:"arrow.uturn.backward").frame(minHeight:44)
                    }.buttonStyle(.bordered).disabled(!board.canUndo).accessibilityIdentifier(game.rawValue+".undo")
                    unifiedBoard(board)
                }.padding(16).frame(maxWidth:760).frame(maxWidth:.infinity)
            }
        }.safeAreaInset(edge:.bottom,spacing:0) {
            if let board {
                Label(model.t(moveHelpKey ?? defaultHelpKey(board)),systemImage:"info.circle")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth:728,alignment:.leading)
                    .padding(12).frame(maxWidth:.infinity).background(.thinMaterial)
                    .accessibilityIdentifier(game.rawValue+".moveHelp")
            }
        }.onChange(of:active) { _,value in if !value { clearInteraction() } }
            .onDisappear { clearInteraction() }
    }
    private func unifiedBoard(_ board: SolitaireBoard) -> some View {
        let layout = SolitaireTableLayout(board: board)
        let scale = min(1, max(1, viewportWidth) / layout.size.width)
        return ZoomBoard(size: layout.size, inputEnabled: active, accessibilityHidden: !active,
                         identifier: game.rawValue + ".zoomBoard", fitWidth: true, cardPan: cardPan(layout)) {
            tableContent(board, layout: layout)
        }
        .frame(height: min(680, layout.size.height * scale))
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { viewportWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        viewportWidth = width
                        cancelDrag()
                    }
            }.allowsHitTesting(false)
        }
    }

    private func tableContent(_ board: SolitaireBoard, layout: SolitaireTableLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if board.variant != .freecell { stockButton(board, frame: layout.stock) }
            if board.variant == .spider {
                Text(model.t("expanded.spider.completed", board.foundations.filter { !$0.isEmpty }.count))
                    .font(.subheadline).padding(.leading, 76).padding(.top, 16)
            }
            ForEach(layout.slots) { slot in
                pileButton(slot, board: board)
            }
            ForEach(board.columns.indices, id: \.self) { column in
                columnContent(column, board: board, layout: layout)
            }
            ForEach(board.tableau.indices, id: \.self) { index in
                if let card = board.tableau[index] {
                    peakCard(card, at: index, board: board, frame: layout.peaks[index])
                }
            }
            if let lifted {
                SolitaireMovingCards(lifted: lifted, finger: finger)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private func stockButton(_ board: SolitaireBoard, frame: CGRect) -> some View {
        let unavailable = board.stock.isEmpty && (board.variant != .klondike || board.waste.isEmpty)
        let emptySpiderColumn = board.variant == .spider && board.columns.contains(where: \.isEmpty)
        let label = model.t("expanded.stock", board.stock.count)
        return Button {
            mutate { $0.stock.isEmpty ? $0.recycle() : $0.draw() }
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8).fill(GameMaterial.teal)
                    .overlay { Image(systemName: board.stock.isEmpty ? "arrow.clockwise" : "rectangle.on.rectangle.angled").foregroundStyle(GameMaterial.gold) }
                    .frame(width: frame.width, height: frame.height)
                pileCaption(label)
            }
        }
        .buttonStyle(.plain).disabled(!active || unavailable || emptySpiderColumn)
        .accessibilityLabel(label).accessibilityIdentifier(game.rawValue + ".draw")
        .position(x: frame.midX, y: frame.midY + 14)
    }

    private func pileCaption(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.primary)
            .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
            .frame(width: 56, height: 24, alignment: .top)
    }

    private func pileButton(_ slot: SolitaireTableLayout.Slot, board: SolitaireBoard) -> some View {
        let place = slot.id
        let cards = board.cards(at: place)
        let top = cards.last
        let label: String
        switch place {
        case .foundation(let index): label = model.t("expanded.foundation", index + 1)
        case .freeCell(let index): label = model.t("expanded.freeCell", index + 1)
        default: label = model.t("expanded.waste")
        }
        let action = { selectPile(place, board: board) }
        return Button(action: action) {
            VStack(spacing: 4) {
                SolitaireCardFace(card: top, faceUp: true,
                                  selected: selected?.place == place || (pyramidSelection == -1 && place == .waste),
                                  suit: top.map(board.effectiveSuit))
                    .frame(width: slot.frame.width, height: slot.frame.height)
                    .opacity(top.map(isLifted) == true ? 0 : 1)
                    .overlay { dropBorder(.pile(place)) }
                pileCaption(label)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!active)
        .accessibilityLabel(label + ", " + (top.map { cardName($0, board: board) } ?? model.t("expanded.empty")))
        .accessibilityIdentifier(game.rawValue + ".pile." + placeID(place))
        .modifier(SolitaireDoubleTap(enabled: autoFoundation(for: .pile(place, index: cards.count - 1), in: board),
                                    singleTap: action, doubleTap: { sendToFoundation(.pile(place, index: cards.count - 1)) }))
        .position(x: slot.frame.midX, y: slot.frame.midY + 14)
    }

    private func selectPile(_ place: CardPlace, board: SolitaireBoard) {
        guard lifted == nil else { return }
        let cards = board.cards(at: place)
        if board.variant == .pyramid, place == .waste {
            if !cards.isEmpty { choosePyramid(-1) }
            return
        }
        if let selected {
            if selected.place == place { self.selected = nil; return }
            if !mutate({ $0.move(from: selected.place, index: selected.index, to: place) }) { showMoveHelp(.pile(place)) }
        } else if !cards.isEmpty {
            selected = CardSelection(place: place, index: cards.count - 1)
            model.feedback(for: game)
        }
    }

    @ViewBuilder private func columnContent(_ column: Int, board: SolitaireBoard, layout: SolitaireTableLayout) -> some View {
        let target = SolitaireDropTarget.pile(.column(column))
        let frame = layout.columnTargets[column]
        if board.columns[column].isEmpty {
            Button {
                if let selected, !mutate({ $0.move(from: selected.place, index: selected.index, to: .column(column)) }) {
                    showMoveHelp(target)
                }
            } label: {
                SolitaireCardFace(card: nil, faceUp: true, selected: false)
                    .frame(width: SolitaireTableLayout.cardSize.width, height: SolitaireTableLayout.cardSize.height)
            }
            .buttonStyle(.plain).disabled(!active).accessibilityLabel(model.t("expanded.column", column + 1))
            .accessibilityIdentifier(game.rawValue + ".column.\(column).empty")
            .position(x: frame.midX, y: frame.minY + SolitaireTableLayout.cardSize.height / 2)
        } else {
            ForEach(Array(board.columns[column].enumerated()), id: \.element.id) { index, card in
                tableauCard(card, column: column, index: index, board: board, frame: layout.columns[column][index])
            }
        }
        dropBorder(target).frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func tableauCard(_ card: PlayingCard, column: Int, index: Int, board: SolitaireBoard, frame: CGRect) -> some View {
        let faceUp = board.faceUp.contains(card.id)
        let choice = CardSelection(place: .column(column), index: index)
        let source = SolitaireDragSource.pile(choice.place, index: index)
        let action = { selectColumnCard(choice) }
        return Button(action: action) {
            SolitaireCardFace(card: card, faceUp: faceUp, selected: selected == choice, suit: board.effectiveSuit(card))
                .frame(width: frame.width, height: frame.height).contentShape(Rectangle())
                .opacity(isLifted(card) ? 0 : 1)
        }
        .buttonStyle(.plain).disabled(!faceUp || !active)
        .accessibilityLabel(faceUp ? cardName(card, board: board) + ", " + model.t("expanded.column", column + 1) : model.t("expanded.card.hidden"))
        .accessibilityIdentifier(game.rawValue + ".card.\(card.id)")
        .modifier(SolitaireDoubleTap(enabled: faceUp && index == board.columns[column].count - 1 && autoFoundation(for: source, in: board),
                                    singleTap: action, doubleTap: { sendToFoundation(source) }))
        .position(x: frame.midX, y: frame.midY)
    }

    private func selectColumnCard(_ choice: CardSelection) {
        guard lifted == nil else { return }
        if let selected, selected.place != choice.place {
            if !mutate({ $0.move(from: selected.place, index: selected.index, to: choice.place) }) {
                showMoveHelp(.pile(choice.place))
            }
        } else {
            selected = selected == choice ? nil : choice
            model.feedback(for: game)
        }
    }

    private func peakCard(_ card: PlayingCard, at index: Int, board: SolitaireBoard, frame: CGRect) -> some View {
        let pyramid = board.variant == .pyramid
        let exposed = board.isExposed(index)
        return Button {
            if pyramid { choosePyramid(index) }
            else if !mutate({ $0.removeTriPeak(index) }) { showMoveHelp(.pile(.waste)) }
        } label: {
            SolitaireCardFace(card: card, faceUp: exposed || pyramid, selected: pyramidSelection == index)
                .frame(width: frame.width, height: frame.height).contentShape(Rectangle())
                .opacity(isLifted(card) ? 0 : 1)
        }
        .buttonStyle(.plain).disabled(!exposed || !active)
        .accessibilityLabel(exposed || pyramid ? cardName(card, board: board) : model.t("expanded.card.hidden"))
        .accessibilityIdentifier(game.rawValue + ".tableau.\(index)")
        .overlay { dropBorder(.tableau(index)) }
        .position(x: frame.midX, y: frame.midY)
    }

    private func choosePyramid(_ index: Int) {
        guard lifted == nil else { return }
        if mutate({$0.removePyramid(index)}) { pyramidSelection = nil; return }
        if let previous = pyramidSelection, previous != index {
            if mutate({$0.removePyramid(previous,index)}) { pyramidSelection = nil; return }
            moveHelpKey = "expanded.pyramid.help"
        }
        pyramidSelection = pyramidSelection==index ? nil : index
    }
    private func defaultHelpKey(_ board: SolitaireBoard) -> String {
        switch board.variant {
        case .klondike,.freecell:return "expanded.solitaire.foundationGesture"
        case .pyramid:return "expanded.pyramid.help"
        case .tripeaks:return "expanded.tripeaks.help"
        default:return "expanded.solitaire.help"
        }
    }
    private func showMoveHelp(_ target: SolitaireDropTarget) {
        guard let board else { return }
        if board.variant == .pyramid || board.variant == .tripeaks { moveHelpKey = defaultHelpKey(board); return }
        switch target {
        case .pile(.foundation):moveHelpKey = "expanded.solitaire.foundationHelp"
        case .pile(.freeCell):moveHelpKey = "expanded.solitaire.cellHelp"
        case .pile(.column(let index)):
            if board.variant == .spider { moveHelpKey = "expanded.solitaire.spiderHelp" }
            else if board.variant == .freecell { moveHelpKey = "expanded.solitaire.freecellHelp" }
            else if board.columns.indices.contains(index),board.columns[index].isEmpty { moveHelpKey = "expanded.solitaire.kingHelp" }
            else { moveHelpKey = "expanded.solitaire.columnHelp" }
        default:moveHelpKey = defaultHelpKey(board)
        }
    }
    @discardableResult private func mutate(_ change: (inout SolitaireBoard) -> Bool) -> Bool {
        guard active, lifted == nil else { return false }
        let changed = model.editExpanded(game) { state in
            guard case .solitaire(var board) = state, change(&board) else { return false }; state = .solitaire(board); return true
        }
        if changed { clearInteraction(); moveHelpKey = nil }
        return changed
    }
    private func clearInteraction() {
        selected = nil
        pyramidSelection = nil
        cancelDrag()
    }

    private func autoFoundation(for source: SolitaireDragSource, in board: SolitaireBoard) -> Bool {
        guard active, board.variant == .klondike || board.variant == .freecell else { return false }
        return SolitaireDragIntent(board: board, source: source)?.foundationTarget(in: board) != nil
    }

    private func sendToFoundation(_ source: SolitaireDragSource) {
        guard let board, let intent = SolitaireDragIntent(board: board, source: source),
              let target = intent.foundationTarget(in: board) else { return }
        mutate { intent.apply(on: target, to: &$0) }
    }

    private func cardPan(_ layout: SolitaireTableLayout) -> BoardCardPan {
        BoardCardPan(canPickUp: { pickup(at: $0, layout: layout) != nil }, began: { origin in
            guard let pickup = pickup(at: origin, layout: layout), let sessionID = model.sessionData.sessions[game]?.id else { return }
            selected = nil
            pyramidSelection = nil
            finger.translation = .zero
            lifted = SolitaireLiftedCards(sessionID: sessionID, intent: pickup.0, origin: origin, frame: pickup.1)
            model.feedback(for: game)
        }, moved: { point in
            guard let lifted, let board, ownsDrag(lifted) else { cancelDrag(); return }
            finger.translation = CGSize(width: point.x - lifted.origin.x, height: point.y - lifted.origin.y)
            let candidate = layout.target(at: point, in: board)
            let legal = candidate.flatMap { lifted.intent.canDrop(on: $0, in: board) ? $0 : nil }
            if hovered != legal { hovered = legal }
        }, ended: { point in
            guard let lifted, let board, ownsDrag(lifted) else { cancelDrag(); return }
            cancelDrag()
            guard let target = layout.target(at: point, in: board) else { return }
            if !mutate({ lifted.intent.apply(on: target, to: &$0) }) { showMoveHelp(target) }
        }, cancelled: cancelDrag)
    }

    private func pickup(at point: CGPoint, layout: SolitaireTableLayout) -> (SolitaireDragIntent, CGRect)? {
        guard active, lifted == nil, let board, let (source, frame) = layout.source(at: point, in: board),
              let intent = SolitaireDragIntent(board: board, source: source) else { return nil }
        return (intent, frame)
    }

    private func ownsDrag(_ drag: SolitaireLiftedCards) -> Bool {
        active && model.sessionData.sessions[game]?.id == drag.sessionID
    }

    private func isLifted(_ card: PlayingCard) -> Bool {
        lifted?.intent.cards.contains(card) == true
    }

    private func cancelDrag() {
        lifted = nil
        hovered = nil
    }

    @ViewBuilder private func dropBorder(_ target: SolitaireDropTarget) -> some View {
        if hovered == target {
            RoundedRectangle(cornerRadius:9).strokeBorder(Color.green,lineWidth:3)
                .shadow(color:.green.opacity(0.3),radius:6).allowsHitTesting(false)
        }
    }
    private func cardName(_ card: PlayingCard,board: SolitaireBoard) -> String { model.t("expanded.card",card.rank,model.t("expanded.suit.\(board.effectiveSuit(card))")) }
    private func placeID(_ place: CardPlace) -> String {
        switch place { case .column(let i):return "column.\(i)"; case .foundation(let i):return "foundation.\(i)"; case .freeCell(let i):return "freecell.\(i)"; case .waste:return "waste" }
    }
}

struct SolitaireFelt: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = colorScheme == .dark
            ? [GameMaterial.teal, GameMaterial.navy]
            : [Color(red: 0.78, green: 0.88, blue: 0.84), Color(red: 0.61, green: 0.79, blue: 0.76)]
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct SolitaireDoubleTap: ViewModifier {
    let enabled: Bool
    let singleTap: () -> Void
    let doubleTap: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(
                TapGesture(count: 2).onEnded { doubleTap() }
                    .exclusively(before: TapGesture().onEnded { singleTap() })
            )
        } else {
            content
        }
    }
}

private struct SolitaireMovingCards: View {
    let lifted: SolitaireLiftedCards
    @ObservedObject var finger: SolitaireFingerPosition

    var body: some View {
        ForEach(Array(lifted.intent.cards.enumerated()), id: \.element.id) { index, card in
            SolitaireCardFace(card: card, faceUp: true, selected: false, suit: lifted.intent.effectiveSuit(card))
                .frame(width: lifted.frame.width, height: lifted.frame.height)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
                .position(x: lifted.frame.midX + finger.translation.width,
                          y: lifted.frame.midY + finger.translation.height + CGFloat(index) * SolitaireTableLayout.faceUpStep)
        }
    }
}

struct SolitaireCardFace: View {
    let card: PlayingCard?
    let faceUp: Bool
    let selected: Bool
    var suit: Int? = nil
    var body: some View {
        ZStack {
            if let card {
                RoundedRectangle(cornerRadius:7).fill(faceUp ? GameMaterial.ivory : GameMaterial.teal)
                if faceUp {
                    let actualSuit = suit ?? card.suit
                    let suitSymbol = ["♠","♥","♣","♦"][actualSuit]
                    let ink = actualSuit == 1 || actualSuit == 3 ? GameMaterial.coral : GameMaterial.ink
                    Text(suitSymbol).font(.system(size: 32)).foregroundStyle(ink.opacity(0.27)).offset(y: 9)
                    HStack(spacing: 3) {
                        Text(card.rankText).font(.system(size: 18, weight: .bold, design: .serif))
                        Text(suitSymbol).font(.system(size: 18))
                    }.foregroundStyle(ink).padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else { Image(systemName:"sparkle").foregroundStyle(GameMaterial.gold).font(.title3) }
            } else {
                RoundedRectangle(cornerRadius:7).fill(GameMaterial.navy.opacity(0.1))
                Image(systemName:"plus").foregroundStyle(GameMaterial.gold.opacity(0.8)).font(.caption)
            }
            RoundedRectangle(cornerRadius:7).strokeBorder(selected ? .blue : GameMaterial.gold,lineWidth:selected ? 3 : 1)
        }.accessibilityHidden(true)
    }
}

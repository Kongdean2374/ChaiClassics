import SwiftUI
import ChaiCore
import UniformTypeIdentifiers

private struct CardSelection: Equatable { let place: CardPlace; let index: Int }
private let solitaireDragType = UTType(exportedAs:"cc.chaihome.chaiclassics.card-move",conformingTo:.data)
private struct SolitaireDragContext {
    let id: UUID
    let sessionID: UUID
    let intent: SolitaireDragIntent
}

struct ExpandedSolitaireView: View {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    @State private var selected: CardSelection?
    @State private var pyramidSelection: Int?
    @State private var dragContext: SolitaireDragContext?
    @State private var hovered: SolitaireDropTarget?
    @State private var dropLoading = false
    @State private var moveHelpKey: String?
    @State private var viewportWidth: CGFloat = 320
    private var board: SolitaireBoard? { if case .solitaire(let board) = model.expandedGames[game]?.state { return board }; return nil }
    private var active: Bool { model.sessionIsPlaying(game) }
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
                    .padding(12).frame(maxWidth:.infinity).background(.regularMaterial)
                    .accessibilityIdentifier(game.rawValue+".moveHelp")
            }
        }.onChange(of:active) { _,value in if !value { clearInteraction() } }
            .onDisappear { clearInteraction() }
    }
    private func unifiedBoard(_ board: SolitaireBoard) -> some View {
        let peaks = board.variant == .pyramid || board.variant == .tripeaks
        let width = peaks ? (board.variant == .pyramid ? 420 : 600) : board.columns.count*64
        let fieldHeight = peaks ? (board.variant == .pyramid ? 410 : 270) : max(140,(board.columns.map(\.count).max() ?? 0)*44+40)
        let height = fieldHeight+136
        // One UIKit hosting root and one zoom transform for the entire table.
        // A drag from the stock/waste row never crosses a separate scroll view.
        return ZoomBoard(size:CGSize(width:width,height:height),inputEnabled:active,accessibilityHidden:!active,
                         identifier:game.rawValue+".zoomBoard") {
            VStack(alignment:.leading,spacing:16) {
                controls(board).frame(width:CGFloat(width-8),height:112,alignment:.topLeading)
                if peaks { peakContent(board).frame(width:CGFloat(width-8),height:CGFloat(fieldHeight),alignment:.topLeading) }
                else { columnContent(board,height:fieldHeight) }
            }.padding(4).frame(width:CGFloat(width),height:CGFloat(height),alignment:.topLeading)
                .background(GameBoardSurface(game:game,cornerRadius:16)).environmentObject(model)
        }.frame(height:min(680,CGFloat(height)*max(1,viewportWidth)/CGFloat(width)))
            .background {
                GeometryReader { proxy in
                    Color.clear.onAppear { viewportWidth = proxy.size.width }
                        .onChange(of:proxy.size.width) { _,width in viewportWidth = width }
                }.allowsHitTesting(false)
            }.background(GameBoardSurface(game:game,cornerRadius:16))
            .clipShape(RoundedRectangle(cornerRadius:16))
    }
    private func controls(_ board: SolitaireBoard) -> some View {
            HStack(alignment:.top,spacing:8) {
                if board.variant != .freecell {
                    Button {
                        mutate { board in if board.stock.isEmpty { return board.recycle() }; return board.draw() }
                    } label: {
                        VStack(spacing:4) {
                            RoundedRectangle(cornerRadius:8).fill(GameMaterial.teal).overlay { Image(systemName:board.stock.isEmpty ? "arrow.clockwise" : "rectangle.on.rectangle.angled").foregroundStyle(GameMaterial.gold) }.frame(width:56,height:76)
                            pileCaption(model.t("expanded.stock",board.stock.count))
                        }
                    }.buttonStyle(.plain).disabled(!active || (board.stock.isEmpty && (board.variant != .klondike || board.waste.isEmpty)) ||
                                                  (board.variant == .spider && board.columns.contains(where:\.isEmpty)))
                        .accessibilityLabel(model.t("expanded.stock",board.stock.count)).accessibilityIdentifier(game.rawValue+".draw")
                }
                if board.variant != .spider && board.variant != .freecell {
                    pile(.waste,board:board,label:model.t("expanded.waste"))
                }
                if board.variant == .freecell {
                    ForEach(0..<4,id:\.self) { i in pile(.freeCell(i),board:board,label:model.t("expanded.freeCell",i+1)) }
                }
                if board.variant == .klondike { Color.clear.frame(width:56,height:76).accessibilityHidden(true) }
                if board.variant == .klondike || board.variant == .freecell {
                    ForEach(0..<4,id:\.self) { i in pile(.foundation(i),board:board,label:model.t("expanded.foundation",i+1)) }
                }
                if board.variant == .spider {
                    Text(model.t("expanded.spider.completed",board.foundations.filter{!$0.isEmpty}.count))
                        .font(.subheadline).foregroundStyle(GameMaterial.ivory).padding(14)
                }
            }.accessibilityIdentifier(game.rawValue+".piles")
    }
    private func pileCaption(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(GameMaterial.ivory)
            .lineLimit(2).multilineTextAlignment(.center).frame(width:56,height:28,alignment:.top)
    }
    private func pile(_ place: CardPlace,board: SolitaireBoard,label: String) -> some View {
        let cards = board.cards(at:place), top = cards.last
        return Button {
            if board.variant == .pyramid, case .waste = place { choosePyramid(-1,board:board); return }
            if let selected {
                if selected.place == place { self.selected = nil; return }
                if !mutate({$0.move(from:selected.place,index:selected.index,to:place)}) { showMoveHelp(.pile(place)) }
                return
            }
            if let top { selected = CardSelection(place:place,index:cards.count-1); model.feedback(for:game); _ = top }
            else { selected = nil }
        } label: {
            VStack(spacing:4) {
                SolitaireCardFace(card:top,faceUp:true,selected:selected?.place==place || (pyramidSelection == -1 && place == .waste),suit:top.map(board.effectiveSuit))
                    .frame(width:56,height:76)
                pileCaption(label)
            }
        }.buttonStyle(.plain).accessibilityLabel(label+", "+(top.map { cardName($0,board:board) } ?? model.t("expanded.empty")))
            .accessibilityIdentifier(game.rawValue+".pile."+placeID(place))
            .modifier(SolitaireCardDrag(intent:active ? SolitaireDragIntent(board:board,source:.pile(place,index:cards.count-1)) : nil,
                                       begin:beginDrag))
            .overlay { dropBorder(.pile(place)) }
            .onDrop(of:[solitaireDragType],delegate:dropDelegate(.pile(place)))
    }
    private func columnContent(_ board: SolitaireBoard,height: Int) -> some View {
            HStack(alignment:.top,spacing:8) {
                ForEach(board.columns.indices,id:\.self) { column in
                    VStack(spacing:0) {
                        if board.columns[column].isEmpty {
                            Button {
                                if let selected, !mutate({$0.move(from:selected.place,index:selected.index,to:.column(column))}) {
                                    showMoveHelp(.pile(.column(column)))
                                }
                            } label: {
                                SolitaireCardFace(card:nil,faceUp:true,selected:false).frame(width:56,height:76)
                            }.buttonStyle(.plain).accessibilityLabel(model.t("expanded.column",column+1))
                                .accessibilityIdentifier(game.rawValue+".column.\(column).empty")
                        }
                        ForEach(Array(board.columns[column].enumerated()),id:\.element.id) { index,card in
                            tableauCard(card,column:column,index:index,board:board)
                        }
                    }.frame(width:56,height:CGFloat(height),alignment:.top)
                        .contentShape(Rectangle())
                        .overlay { dropBorder(.pile(.column(column))) }
                        .onDrop(of:[solitaireDragType],delegate:dropDelegate(.pile(.column(column))))
                }
            }
    }
    private func tableauCard(_ card: PlayingCard,column: Int,index: Int,board: SolitaireBoard) -> some View {
        let faceUp = board.faceUp.contains(card.id), selection = CardSelection(place:.column(column),index:index)
        return Button {
            if let selected, selected.place != .column(column) {
                if !mutate({$0.move(from:selected.place,index:selected.index,to:.column(column))}) { showMoveHelp(.pile(.column(column))) }
                return
            }
            selected = self.selected==selection ? nil : selection; model.feedback(for:game)
        } label: {
            SolitaireCardFace(card:card,faceUp:faceUp,selected:selected==selection,suit:board.effectiveSuit(card))
                .frame(width:56,height:76).frame(height:index==board.columns[column].count-1 ? 76 : 44,alignment:.top).clipped()
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!faceUp || !active).accessibilityHidden(!active)
            .accessibilityLabel(faceUp ? cardName(card,board:board)+", "+model.t("expanded.column",column+1) : model.t("expanded.card.hidden"))
            .accessibilityIdentifier(game.rawValue+".card.\(card.id)")
            .modifier(SolitaireCardDrag(intent:active ? SolitaireDragIntent(board:board,source:.pile(.column(column),index:index)) : nil,
                                       begin:beginDrag))
    }
    private func peakContent(_ board: SolitaireBoard) -> some View {
        let pyramid = board.variant == .pyramid
        return ZStack(alignment:.topLeading) {
                Color.clear
                ForEach(board.tableau.indices,id:\.self) { index in
                    if let card = board.tableau[index] {
                        let point = peakPosition(index,pyramid:pyramid), exposed = board.isExposed(index)
                        Button {
                            if pyramid { choosePyramid(index,board:board) }
                            else if !mutate({$0.removeTriPeak(index)}) { showMoveHelp(.pile(.waste)) }
                        } label: {
                            SolitaireCardFace(card:card,faceUp:exposed || pyramid,selected:pyramidSelection==index)
                                .frame(width:52,height:72).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!exposed || !active)
                            .accessibilityHidden(!active).accessibilityLabel(exposed || pyramid ? cardName(card,board:board) : model.t("expanded.card.hidden"))
                            .accessibilityIdentifier(game.rawValue+".tableau.\(index)")
                            .modifier(SolitaireCardDrag(intent:active ? SolitaireDragIntent(board:board,source:.tableau(index)) : nil,
                                                       begin:beginDrag))
                            .overlay { dropBorder(.tableau(index)) }
                            .onDrop(of:[solitaireDragType],delegate:dropDelegate(.tableau(index)))
                            .offset(x:point.x,y:point.y)
                    }
                }
            }
    }
    private func peakPosition(_ index: Int,pyramid: Bool) -> CGPoint {
        if pyramid {
            var row = 0; while (row+1)*(row+2)/2<=index { row += 1 }
            let column = index-row*(row+1)/2
            return CGPoint(x:CGFloat(6-row)*29+CGFloat(column)*58+8,y:CGFloat(row)*54+8)
        }
        if index<3 { return CGPoint(x:CGFloat(index)*174+64,y:8) }
        if index<9 { let n = index-3; return CGPoint(x:CGFloat(n/2)*174+CGFloat(n%2)*58+35,y:62) }
        if index<18 { let n = index-9; return CGPoint(x:CGFloat(n/3)*174+CGFloat(n%3)*58+6,y:116) }
        return CGPoint(x:CGFloat(index-18)*58+6,y:170)
    }
    private func choosePyramid(_ index: Int,board: SolitaireBoard) {
        if mutate({$0.removePyramid(index)}) { pyramidSelection = nil; return }
        if let previous = pyramidSelection, previous != index {
            if mutate({$0.removePyramid(previous,index)}) { pyramidSelection = nil; return }
            moveHelpKey = "expanded.pyramid.help"
        }
        pyramidSelection = pyramidSelection==index ? nil : index
    }
    private func defaultHelpKey(_ board: SolitaireBoard) -> String {
        switch board.variant {
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
        let changed = model.editExpanded(game) { state in
            guard case .solitaire(var board) = state, change(&board) else { return false }; state = .solitaire(board); return true
        }
        if changed { clearInteraction(); moveHelpKey = nil }
        return changed
    }
    private func clearInteraction() {
        selected = nil; pyramidSelection = nil; dragContext = nil; hovered = nil; dropLoading = false
    }
    private func beginDrag(_ intent: SolitaireDragIntent) -> NSItemProvider {
        guard active, let board, let sessionID = model.sessionData.sessions[game]?.id,
              let current = SolitaireDragIntent(board:board,source:intent.source) else { return NSItemProvider() }
        let context = SolitaireDragContext(id:UUID(),sessionID:sessionID,intent:current)
        dragContext = context; dropLoading = false; hovered = nil
        switch current.source {
        case .pile(let place,let index): selected = CardSelection(place:place,index:index)
        case .tableau(let index): pyramidSelection = index
        }
        model.feedback(for:game)
        let data = Data(context.id.uuidString.utf8), provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier:solitaireDragType.identifier,visibility:.ownProcess) { completion in
            completion(data,nil); return nil
        }
        return provider
    }
    private func canDrop(_ target: SolitaireDropTarget) -> Bool {
        guard active, !dropLoading, let board, let context = dragContext,
              context.sessionID == model.sessionData.sessions[game]?.id else { return false }
        return context.intent.canDrop(on:target,in:board)
    }
    private func dropDelegate(_ target: SolitaireDropTarget) -> SolitaireCardDrop {
        SolitaireCardDrop(localDrag:{
            active && !dropLoading && dragContext != nil && dragContext?.sessionID == model.sessionData.sessions[game]?.id
        },canDrop:{canDrop(target)},hover:{ value in
            if value { hovered = target } else if hovered == target { hovered = nil }
        },reject:{showMoveHelp(target)},perform:{ info in
            guard canDrop(target), let context = dragContext,
                  let provider = info.itemProviders(for:[solitaireDragType.identifier]).first else { return false }
            dropLoading = true; hovered = nil
            _ = provider.loadDataRepresentation(forTypeIdentifier:solitaireDragType.identifier) { data,_ in
                Task { @MainActor in
                    guard dragContext?.id == context.id else { return }
                    defer { clearInteraction() }
                    guard data == Data(context.id.uuidString.utf8), active,
                          context.sessionID == model.sessionData.sessions[game]?.id else { return }
                    if !mutate({ context.intent.apply(on:target,to:&$0) }) { showMoveHelp(target) }
                }
            }
            return true
        })
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

private struct SolitaireCardDrag: ViewModifier {
    let intent: SolitaireDragIntent?
    let begin: (SolitaireDragIntent) -> NSItemProvider
    @ViewBuilder func body(content: Content) -> some View {
        if let intent {
            content.onDrag { begin(intent) } preview: {
                VStack(spacing:-50) {
                    ForEach(Array(intent.cards.prefix(5))) { card in
                        SolitaireCardFace(card:card,faceUp:true,selected:true,suit:intent.effectiveSuit(card))
                            .frame(width:66,height:90)
                    }
                }.padding(5).overlay(alignment:.topTrailing) {
                    if intent.cards.count > 1 {
                        Text(String(intent.cards.count)).font(.caption.bold()).foregroundStyle(GameMaterial.ink)
                            .padding(6).background(GameMaterial.gold,in:Circle())
                    }
                }
            }
        } else { content }
    }
}

private struct SolitaireCardDrop: DropDelegate {
    let localDrag: () -> Bool
    let canDrop: () -> Bool
    let hover: (Bool) -> Void
    let reject: () -> Void
    let perform: (DropInfo) -> Bool
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to:[solitaireDragType.identifier]) && localDrag() }
    func dropEntered(info: DropInfo) {
        guard validateDrop(info:info) else { return }
        let accepted = canDrop(); hover(accepted)
        if !accepted { reject() }
    }
    func dropExited(info: DropInfo) { hover(false) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation:validateDrop(info:info) && canDrop() ? .move : .cancel) }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info:info) else { return false }
        guard canDrop() else { reject(); hover(false); return false }
        return perform(info)
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
                    VStack(alignment:.leading,spacing:1) {
                        Text(card.rankText).font(.system(size:18,weight:.bold,design:.serif))
                        Text(["♠","♥","♣","♦"][actualSuit]).font(.system(size:21))
                        Spacer(minLength:0)
                    }.foregroundStyle(actualSuit==1 || actualSuit==3 ? GameMaterial.coral : GameMaterial.ink)
                        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).padding(5)
                } else { Image(systemName:"sparkle").foregroundStyle(GameMaterial.gold).font(.title3) }
            } else {
                RoundedRectangle(cornerRadius:7).fill(GameMaterial.navy.opacity(0.1))
                Image(systemName:"plus").foregroundStyle(GameMaterial.gold.opacity(0.8)).font(.caption)
            }
            RoundedRectangle(cornerRadius:7).strokeBorder(selected ? .blue : GameMaterial.gold,lineWidth:selected ? 3 : 1)
        }.accessibilityHidden(true)
    }
}

import SwiftUI
import ChaiCore

struct ExpandedPuzzleView: View {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    @State private var cross = false
    @State private var selected: Int?
    private var state: ExpandedGameState? { model.expandedGames[game]?.state }
    private var active: Bool { model.sessionIsPlaying(game) }
    var body: some View {
        ScrollView {
            VStack(spacing:18) {
                HStack {
                    GameArtwork(game:game,size:46)
                    Text(model.gameTitle(game)).font(.headline)
                    Spacer()
                    Text(model.t("expanded.moves",state?.moves ?? 0)).monospacedDigit().font(.subheadline)
                }
                switch state {
                case .nonogram(let board): nonogram(board)
                case .kakuro(let board): kakuro(board)
                case .klotski(let board): klotski(board)
                default: EmptyView()
                }
            }.padding(16).frame(maxWidth:680).frame(maxWidth:.infinity)
        }.onChange(of:active) { _,playing in if !playing { selected = nil } }
    }
    private func nonogram(_ board: NonogramBoard) -> some View {
        let rowWidth = CGFloat(max(70,(board.rowClues.map { $0.map(String.init).joined(separator:" ").count }.max() ?? 0)*7+12))
        let columnHeight = CGFloat(max(60,(board.columnClues.map(\.count).max() ?? 0)*16+8))
        return VStack(spacing:16) {
            Picker(model.t("expanded.nonogram.tool"),selection:$cross) {
                Text(model.t("expanded.nonogram.fill")).tag(false)
                Text(model.t("expanded.nonogram.cross")).tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("nonogram.tools")
            ZoomBoard(size:CGSize(width:rowWidth+CGFloat(board.size*32),height:columnHeight+CGFloat(board.size*32)),inputEnabled:active,
                      accessibilityHidden:!active,identifier:"nonogram.zoomBoard") {
                VStack(spacing:0) {
                    HStack(alignment:.bottom,spacing:0) {
                        Color.clear.frame(width:rowWidth,height:columnHeight)
                        ForEach(0..<board.size,id:\.self) { column in
                            Text(board.columnClues[column].map(String.init).joined(separator:"\n"))
                                .font(.system(size:11,weight:.bold,design:.rounded)).monospacedDigit()
                                .foregroundStyle(GameMaterial.ivory).multilineTextAlignment(.center)
                                .lineSpacing(2).frame(width:32,height:columnHeight-4,alignment:.bottom).padding(.bottom,4)
                        }
                    }.frame(height:columnHeight)
                    ForEach(0..<board.size,id:\.self) { row in
                        HStack(spacing:0) {
                            Text(board.rowClues[row].map(String.init).joined(separator:" ")).font(.system(size:11,weight:.bold,design:.rounded))
                                .monospacedDigit().foregroundStyle(GameMaterial.ivory).frame(width:rowWidth-4,alignment:.trailing).padding(.trailing,4)
                            ForEach(0..<board.size,id:\.self) { column in nonogramCell(board,index:row*board.size+column) }
                        }.frame(height:32)
                    }
                }.background(GameMaterial.navy)
            }.frame(height:min(620,columnHeight+CGFloat(board.size*32)))
                .background(GameBoardSurface(game:game,cornerRadius:16))
            Text(model.t("expanded.nonogram.help")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func nonogramCell(_ board: NonogramBoard,index: Int) -> some View {
        Button {
            _ = model.editExpanded(game) { state in
                guard case .nonogram(var b) = state, b.mark(index,crossed:cross) else { return false }; state = .nonogram(b); return true
            }
        } label: {
            ZStack {
                Rectangle().fill(board.marks[index]==1 ? GameMaterial.gold : GameMaterial.ivory)
                if board.marks[index] == -1 { Image(systemName:"xmark").font(.system(size:15,weight:.semibold)).foregroundStyle(GameMaterial.ink) }
                Rectangle().strokeBorder(GameMaterial.ink.opacity(index%board.size%5==0 ? 0.65 : 0.22),lineWidth:1)
            }.frame(width:32,height:32).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!active).accessibilityHidden(!active)
            .accessibilityLabel(model.t("expanded.cell",index/board.size+1,index%board.size+1))
            .accessibilityValue(model.t(board.marks[index]==1 ? "expanded.nonogram.filled" : board.marks[index] == -1 ? "expanded.nonogram.crossed" : "expanded.empty"))
            .accessibilityIdentifier("nonogram.cell.\(index)")
    }
    private func kakuro(_ board: KakuroBoard) -> some View {
        VStack(spacing:16) {
            ZoomBoard(size:CGSize(width:board.size*44,height:board.size*44),inputEnabled:active,
                      accessibilityHidden:!active,identifier:"kakuro.zoomBoard") {
                VStack(spacing:0) {
                    ForEach(0..<board.size,id:\.self) { row in
                        HStack(spacing:0) { ForEach(0..<board.size,id:\.self) { column in kakuroCell(board,index:row*board.size+column) } }
                    }
                }.background(GameMaterial.navy)
            }.frame(height:CGFloat(board.size*44+12)).background(GameBoardSurface(game:game,cornerRadius:16))
            Text(model.t("expanded.kakuro.selection")).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:5),spacing:10) {
                ForEach(1...9,id:\.self) { digit in digitButton(digit,board:board) }
                Button { enterKakuro(0) } label: { Image(systemName:"eraser").frame(maxWidth:.infinity,minHeight:48) }
                    .buttonStyle(.bordered).disabled(selected==nil).accessibilityLabel(model.t("sudoku.erase"))
                    .accessibilityIdentifier("kakuro.erase")
            }
        }
    }
    @ViewBuilder private func kakuroCell(_ board: KakuroBoard,index: Int) -> some View {
        if board.solution[index] == -1 {
            ZStack {
                Rectangle().fill(GameMaterial.navy)
                let runs = board.runs.filter{$0.clueIndex==index}
                if !runs.isEmpty {
                    Path { p in p.move(to:.zero); p.addLine(to:CGPoint(x:44,y:44)) }.stroke(GameMaterial.gold.opacity(0.7),lineWidth:1)
                    if let across = runs.first(where:{$0.horizontal}) { Text(String(across.total)).font(.system(size:11,weight:.bold)).foregroundStyle(GameMaterial.ivory).offset(x:10,y:-10) }
                    if let down = runs.first(where:{!$0.horizontal}) { Text(String(down.total)).font(.system(size:11,weight:.bold)).foregroundStyle(GameMaterial.ivory).offset(x:-10,y:10) }
                }
            }.frame(width:44,height:44).accessibilityElement(children:.combine)
        } else {
            Button { selected = index; model.feedback(for:game) } label: {
                Text(board.cells[index]==0 ? " " : String(board.cells[index]))
                    .font(.system(size:23,weight:board.givens[index]>0 ? .bold : .medium,design:.rounded))
                    .foregroundStyle(board.givens[index]>0 ? GameMaterial.ink : Color.blue)
                    .frame(width:44,height:44).background(GameTileSurface(game:game,selected:selected==index,cornerRadius:3))
            }.buttonStyle(.plain).disabled(!active || board.givens[index]>0).accessibilityHidden(!active)
                .accessibilityLabel(model.t("expanded.cell",index/board.size+1,index%board.size+1))
                .accessibilityValue(board.cells[index]==0 ? model.t("expanded.empty") : String(board.cells[index]))
                .accessibilityIdentifier("kakuro.cell.\(index)")
        }
    }
    private func digitButton(_ digit: Int,board: KakuroBoard) -> some View {
        Button { enterKakuro(digit) } label: {
            Text(String(digit)).font(.title2.weight(.semibold)).frame(maxWidth:.infinity,minHeight:48)
        }.buttonStyle(.bordered).disabled(selected==nil).accessibilityIdentifier("kakuro.digit.\(digit)")
    }
    private func enterKakuro(_ value: Int) {
        guard let selected else { return }
        _ = model.editExpanded(game) { state in
            guard case .kakuro(var b) = state, b.enter(value,at:selected) else { return false }; state = .kakuro(b); return true
        }
    }
    private func klotski(_ board: KlotskiBoard) -> some View {
        VStack(spacing:18) {
            GeometryReader { proxy in
                let unit = proxy.size.width/4
                ZStack(alignment:.topLeading) {
                    GameBoardSurface(game:game,cornerRadius:14)
                    ForEach(board.pieces) { piece in
                        Button { selected = piece.id } label: {
                            Text(piece.id==0 ? model.t("expanded.klotski.goal") : "\(piece.id)")
                                .font(piece.id==0 ? .title3.bold() : .title2.bold()).foregroundStyle(GameMaterial.ink)
                                .frame(width:CGFloat(piece.width)*unit-6,height:CGFloat(piece.height)*unit-6)
                                .background(GameTileSurface(game:game,selected:selected==piece.id,cornerRadius:12))
                        }.buttonStyle(.plain).offset(x:CGFloat(piece.x)*unit+3,y:CGFloat(piece.y)*unit+3)
                            .accessibilityLabel(model.t("expanded.klotski.piece",piece.id+1))
                            .accessibilityIdentifier("klotski.piece.\(piece.id)")
                            .simultaneousGesture(DragGesture(minimumDistance:16).onEnded { value in
                                selected = piece.id
                                let dx = abs(value.translation.width)>abs(value.translation.height) ? (value.translation.width>0 ? 1 : -1) : 0
                                let dy = dx==0 ? (value.translation.height>0 ? 1 : -1) : 0
                                moveKlotski(piece.id,dx:dx,dy:dy)
                            })
                    }
                }
            }.aspectRatio(4.0/5,contentMode:.fit).frame(maxWidth:440)
            Text(model.t("expanded.klotski.help")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing:12) {
                ForEach(ArcadeDirection.allCases,id:\.self) { direction in
                    Button { if let selected { moveKlotski(selected,dx:direction.dx,dy:direction.dy) } } label: {
                        Image(systemName:["arrow.up","arrow.right","arrow.down","arrow.left"][direction.rawValue]).frame(minWidth:48,minHeight:48)
                    }.buttonStyle(.bordered).disabled(selected==nil)
                        .accessibilityLabel(model.t("expanded.direction.\(direction.rawValue)"))
                        .accessibilityIdentifier("klotski.move.\(direction.rawValue)")
                }
            }
        }
    }
    private func moveKlotski(_ id: Int,dx: Int,dy: Int) {
        _ = model.editExpanded(game) { state in
            guard case .klotski(var b) = state, b.move(id,dx:dx,dy:dy) else { return false }; state = .klotski(b); return true
        }
    }
}

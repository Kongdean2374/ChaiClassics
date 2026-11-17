import SwiftUI
import UIKit
import ChaiCore

enum GamePalette {
    private static let sudoku = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.71, green: 0.68, blue: 1, alpha: 1) : UIColor(red: 0.34, green: 0.29, blue: 0.74, alpha: 1)
    })
    private static let mines = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.44, green: 0.84, blue: 0.76, alpha: 1) : UIColor(red: 0.055, green: 0.43, blue: 0.39, alpha: 1)
    })
    private static let sliding = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.97, green: 0.73, blue: 0.40, alpha: 1) : UIColor(red: 0.61, green: 0.31, blue: 0.02, alpha: 1)
    })
    private static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static func tint(_ accent: CatalogAccent) -> Color {
        switch accent {
        case .violet: return sudoku
        case .jade: return mines
        case .amber: return sliding
        case .rose: return adaptive(UIColor(red: 0.66, green: 0.18, blue: 0.40, alpha: 1), UIColor(red: 1, green: 0.63, blue: 0.77, alpha: 1))
        case .blue: return adaptive(UIColor(red: 0.15, green: 0.36, blue: 0.69, alpha: 1), UIColor(red: 0.55, green: 0.75, blue: 1, alpha: 1))
        case .coral: return adaptive(UIColor(red: 0.68, green: 0.27, blue: 0.16, alpha: 1), UIColor(red: 1, green: 0.68, blue: 0.53, alpha: 1))
        case .teal: return adaptive(UIColor(red: 0.08, green: 0.43, blue: 0.49, alpha: 1), UIColor(red: 0.44, green: 0.83, blue: 0.89, alpha: 1))
        case .indigo: return adaptive(UIColor(red: 0.34, green: 0.31, blue: 0.67, alpha: 1), UIColor(red: 0.73, green: 0.70, blue: 1, alpha: 1))
        case .slate: return adaptive(UIColor(red: 0.31, green: 0.36, blue: 0.44, alpha: 1), UIColor(red: 0.72, green: 0.77, blue: 0.85, alpha: 1))
        }
    }
    static func tint(_ game: GameID) -> Color {
        tint(GameCatalog.item(for: game)?.accent ?? .violet)
    }
}

/// A static backdrop: no blur, moving gradients or recurring rendering work.
struct GameCanvas: View {
    var body: some View {
        Color(.systemGroupedBackground)
            .overlay(alignment: .top) {
                LinearGradient(colors: [.indigo.opacity(0.045), .teal.opacity(0.02), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 420)
            }.ignoresSafeArea()
    }
}

/// Original, vector-drawn game artwork. Decorative cells never expose live answers.
struct GameArtwork: View {
    let game: GameID
    var size: CGFloat = 72
    private var tint: Color { GamePalette.tint(game) }
    var body: some View {
        Canvas { context, bounds in
            if game != .sudoku && game != .minesweeper && game != .sliding {
                var symbol = context.resolve(Image(systemName: GameCatalog.item(for: game)?.symbol ?? "square.grid.3x3"))
                symbol.shading = .color(tint)
                context.draw(symbol, in: CGRect(origin: .zero, size: bounds).insetBy(dx: bounds.width * 0.22, dy: bounds.height * 0.22))
                return
            }
            let inset = bounds.width * 0.17
            let gap = bounds.width * 0.035
            let side = (bounds.width - inset * 2 - gap * 2) / 3
            for index in 0..<9 {
                let rect = CGRect(x: inset + CGFloat(index % 3) * (side + gap),
                                  y: inset + CGFloat(index / 3) * (side + gap), width: side, height: side)
                let blank = game == .sliding && index == 8
                let path = Path(roundedRect: rect, cornerRadius: max(2, side * 0.18))
                context.fill(path, with: .color(tint.opacity(blank ? 0.04 : game == .minesweeper ? 0.16 : 0.11)))
                context.stroke(path, with: .color(tint.opacity(blank ? 0.12 : 0.2)), lineWidth: 0.7)
                if game == .sliding && !blank {
                    draw(String(index + 1), in: &context, at: rect, size: side * 0.61)
                } else if game == .sudoku && [0, 2, 4, 6, 8].contains(index) {
                    let digits = [0: "1", 2: "7", 4: "5", 6: "9", 8: "3"]
                    draw(digits[index] ?? "", in: &context, at: rect, size: side * 0.66)
                } else if game == .minesweeper && index == 4 {
                    var flag = context.resolve(Image(systemName: "flag.fill"))
                    flag.shading = .color(tint)
                    context.draw(flag, in: rect.insetBy(dx: side * 0.2, dy: side * 0.17))
                } else if game == .minesweeper && [0, 2, 6, 8].contains(index) {
                    draw("1", in: &context, at: rect, size: side * 0.56)
                }
            }
        }.frame(width: size, height: size)
            .background(LinearGradient(colors: [tint.opacity(0.12), tint.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.25))
            .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(tint.opacity(0.16), lineWidth: 1))
            .accessibilityHidden(true)
    }
    private func draw(_ value: String, in context: inout GraphicsContext, at rect: CGRect, size: CGFloat) {
        let text = Text(value).font(.system(size: size, weight: .semibold, design: .rounded)).foregroundColor(tint)
        context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
    }
}

/// Catalog previews use the same rounded vector-art tiles as playable games.
/// No remote artwork or board state is involved.
struct CatalogArtwork: View {
    let item: CatalogItem
    var size: CGFloat = 72
    private var tint: Color { GamePalette.tint(item.accent) }

    @ViewBuilder var body: some View {
        if let game = item.gameID {
            GameArtwork(game: game, size: size)
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(LinearGradient(colors: [tint.opacity(0.12), tint.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.25))
                .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(tint.opacity(0.16), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
}

struct QuietPressStyle: ButtonStyle {
    @Environment(\.gameReducedMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct GameIntroHeader: View {
    let game: GameID
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                GameArtwork(game: game, size: 62)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            GameStorageRecoveryView(game: game)
        }
    }
}

struct GameMetric: View {
    let symbol: String
    let value: String
    var tint: Color = .accentColor
    var identifier: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            Text(value).monospacedDigit().foregroundStyle(.primary)
                .accessibilityIdentifier(identifier ?? "")
        }.font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 9)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct GameResultBanner: View {
    let game: GameID
    let title: String
    let detail: String
    let won: Bool
    var identifier: String? = nil
    private var tint: Color { won ? GamePalette.tint(game) : .secondary }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: won ? "checkmark.seal.fill" : "flag.checkered")
                .font(.title2).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).accessibilityIdentifier(identifier ?? "")
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(tint.opacity(0.16), lineWidth: 1))
    }
}

struct PauseCard: View {
    let game: GameID
    let action: () -> Void
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "pause.circle").font(.system(size: 44, weight: .light)).foregroundStyle(GamePalette.tint(game)).accessibilityHidden(true)
            Text(model.t("game.paused")).font(.system(.title3, design: .rounded, weight: .semibold))
            Button(action: action) {
                Label(model.t("common.resume"), systemImage: "play.fill").padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(Color(.systemBackground))
            }.buttonStyle(.borderedProminent).tint(GamePalette.tint(game)).accessibilityIdentifier("game.resume")
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(GamePalette.tint(game).opacity(0.12), lineWidth: 1))
    }
}

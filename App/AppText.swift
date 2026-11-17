import Foundation
import ChaiCore

struct AppText {
    let language: AppLanguage
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
    func text(_ key: String, _ arguments: [CVarArg] = []) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}

extension AppModel {
    func t(_ key: String, _ arguments: CVarArg...) -> String { AppText(language: preferences.language).text(key, arguments) }
    func gameTitle(_ id: GameID) -> String { t("game." + id.rawValue) }
    func summary(_ id: GameID) -> GameSummary {
        switch id {
        case .sudoku: return .sudoku(sudoku, catalog: puzzles)
        case .minesweeper: return .mines(mines)
        case .sliding: return .sliding(sliding)
        // New games present their own session details after entering the menu.
        default: return .empty
        }
    }
    func summaryDetail(_ summary: GameSummary) -> String {
        switch summary.detail {
        case .none: return t("home.ready")
        case let .sudoku(difficulty, number, filled, total):
            return t("sudoku.level.detail", t("difficulty." + difficulty.rawValue), number, filled, total)
        case let .mines(config, flags, _):
            return t("mines.summary", t(config.difficultyKey), config.width, config.height, flags, config.mineCount)
        case let .sliding(size, difficulty, moves, _):
            return t("sliding.summary", size, size, t("difficulty." + difficulty.rawValue), moves)
        }
    }
}

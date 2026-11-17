import SwiftUI
import UniformTypeIdentifiers
import ChaiCore

/// User-selected local game backups. This document has no network transport.
struct GameDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func filename(game: String? = nil, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let scope = game.map { "-" + $0 } ?? ""
        return "ChaiClassics" + scope + "-" + formatter.string(from: now)
    }

    static func readUserSelectedFile(_ url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= 16 * 1024 * 1024 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
}

/// A single local document operation owns the native picker at a time. Import
/// previews stay inline, so another modal never competes with the Files picker.
struct GameDataTransferSection: View {
    let game: GameID?
    var allowsImport = false
    @Binding var isBusy: Bool
    var locked = false
    @EnvironmentObject private var model: AppModel
    @State private var phase: Phase = .idle
    @State private var exportDocument: GameDataDocument?
    @State private var exportFilename = "ChaiClassics"
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showConfirmation = false
    @State private var pending: PendingImport?
    @State private var operationID: UUID?
    @State private var statusKey: String?
    @State private var failed = false

    private enum Phase { case idle, exporting, importing, preview, committing }
    private struct PendingImport {
        let data: Data
        let summary: GameDataImportPreview
    }

    var body: some View {
        let callbackID = operationID
        Section {
            Button(action: beginExport) {
                Label(model.t(game == nil ? "data.export.all" : "data.export.game"), systemImage: "square.and.arrow.up")
            }.disabled(phase != .idle || locked).accessibilityIdentifier("data.export")
            if allowsImport {
                Button(action: beginImport) {
                    Label(model.t("data.import"), systemImage: "square.and.arrow.down")
                }.disabled(phase != .idle || locked).accessibilityIdentifier("data.import")
            }
            if let pending { preview(pending.summary) }
            if let statusKey {
                Label(model.t(statusKey), systemImage: failed ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.footnote).foregroundStyle(failed ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("data.status")
            }
        } header: {
            Text(model.t("data.title"))
        } footer: {
            Text(model.t("data.detail"))
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                      defaultFilename: exportFilename) { result in
            guard let callbackID, callbackID == operationID else { return }
            if case let .failure(error) = result {
                if !isCancellation(error) { statusKey = "data.export.failed"; failed = true }
            } else { statusKey = "data.export.success"; failed = false }
            exportDocument = nil; phase = .idle; isBusy = false; operationID = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard let callbackID, callbackID == operationID else { return }
            switch result {
            case let .success(url):
                do {
                    let data = try GameDataDocument.readUserSelectedFile(url)
                    let summary = try model.previewGameDataImport(data)
                    pending = PendingImport(data: data, summary: summary)
                    phase = .preview; isBusy = true
                } catch { finishFailure("data.import.invalid") }
            case let .failure(error):
                if isCancellation(error) { phase = .idle; isBusy = false }
                else { finishFailure("data.import.failed") }
            }
        }
        .onChange(of: showExporter) { old, presented in
            // SwiftUI need not invoke completion when the user cancels a picker.
            if old && !presented && phase == .exporting { phase = .idle; isBusy = false }
        }
        .onChange(of: showImporter) { old, presented in
            if old && !presented && phase == .importing { phase = .idle; isBusy = false }
        }
        .gameActionConfirmation(title: model.t("data.import.confirm.title"),
                                message: model.t("data.import.confirm.detail"),
                                isPresented: $showConfirmation, confirmTitle: model.t("data.import.confirm"),
                                onConfirm: commitImport)
    }

    private func preview(_ summary: GameDataImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.t("data.preview.title"), systemImage: "doc.text.magnifyingglass").font(.headline)
            Text(model.t("data.preview.detail")).font(.subheadline).foregroundStyle(.secondary)
            LabeledContent(model.t("data.preview.created"), value: GameRecordText.date(summary.createdAt, model: model))
            LabeledContent(model.t("data.preview.games"), value: summary.games.map { model.gameTitle($0) }
                .joined(separator: model.preferences.language == .english ? ", " : "、"))
            LabeledContent(model.t("data.preview.records"), value: String(summary.recordCount))
            LabeledContent(model.t("data.preview.preferences"),
                           value: model.t(summary.includesPreferences ? "data.included" : "data.notIncluded"))
            HStack {
                Button(model.t("common.cancel")) {
                    guard phase == .preview, !showConfirmation else { return }
                    pending = nil; phase = .idle; isBusy = false; operationID = nil
                }.accessibilityIdentifier("data.import.cancelPreview")
                Spacer()
                Button(model.t("data.import.reviewed"), role: .destructive) {
                    guard phase == .preview, !showConfirmation else { return }
                    showConfirmation = true
                }.accessibilityIdentifier("data.import.reviewed")
            }.buttonStyle(.bordered)
        }.padding(.vertical, 6).accessibilityIdentifier("data.import.preview")
    }

    private func beginExport() {
        guard phase == .idle, !locked else { return }
        operationID = UUID(); phase = .exporting; isBusy = true; statusKey = nil
        do {
            exportDocument = GameDataDocument(data: try model.exportGameData(game: game))
            exportFilename = GameDataDocument.filename(game: game?.rawValue)
            showExporter = true
        } catch { finishFailure("data.export.failed") }
    }
    private func beginImport() {
        guard phase == .idle, !locked else { return }
        operationID = UUID(); phase = .importing; isBusy = true; statusKey = nil; showImporter = true
    }
    private func commitImport() {
        guard phase == .preview, let backup = pending else { return }
        phase = .committing
        do {
            // Revalidate at the actual commit point; preview never changes saves.
            try model.importGameData(backup.data)
            pending = nil; statusKey = "data.import.success"; failed = false
            phase = .idle; isBusy = false; operationID = nil
        } catch { finishFailure("data.import.failed") }
    }
    private func finishFailure(_ key: String) {
        pending = nil; exportDocument = nil; statusKey = key; failed = true
        phase = .idle; isBusy = false; operationID = nil
    }
    private func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == CocoaError.userCancelled.rawValue
    }
}

import Foundation
import Photos

@MainActor
@Observable
final class ExportViewModel {
    let match: Match
    let exportService = VideoExportService()

    var showShareSheet = false
    var savedToPhotos = false
    var saveError: String?

    /// 確認画面に表示する出力の見込み
    struct OutputPreview {
        let renderSize: CGSize
        let frameRate: Double
        /// 見積もれなかった場合は nil
        let estimatedFileSize: Int64?
    }

    private(set) var outputPreview: OutputPreview?
    private(set) var isLoadingOutputPreview = false

    init(match: Match) {
        self.match = match
    }

    func loadOutputPreview() async {
        guard outputPreview == nil, !isLoadingOutputPreview else { return }
        isLoadingOutputPreview = true
        defer { isLoadingOutputPreview = false }

        guard let plan = try? await VideoExportService.makePlan(
            urls: match.videoURLs,
            skipOverlay: match.skipOverlay
        ) else { return }
        let fileSize = await VideoExportService.estimatedFileSize(for: plan)
        outputPreview = OutputPreview(
            renderSize: plan.renderSize,
            frameRate: plan.frameRate,
            estimatedFileSize: fileSize
        )
    }

    var progress: Float { exportService.progress }
    var isExporting: Bool { exportService.isExporting }
    var exportedURL: URL? { exportService.exportedURL }
    var exportError: Error? { exportService.error }

    /// エラーがユーザーによるキャンセルかどうか（失敗表示と区別するため）
    var isCancelledByUser: Bool {
        if case VideoExportService.ExportError.cancelled? = exportError as? VideoExportService.ExportError {
            return true
        }
        return false
    }

    func startExport() {
        Task {
            do {
                _ = try await exportService.export(match: match)
            } catch {
                // Error is captured in exportService.error
            }
        }
    }

    func cancelExport() {
        exportService.cancel()
    }

    func cleanupExportedFile() {
        exportService.cleanupExportedFile()
    }

    func saveToPhotos() {
        guard let url = exportedURL else { return }
        saveError = nil

        Task {
            do {
                try await PhotoLibrarySaver.save(videoAt: url)
                savedToPhotos = true
            } catch PhotoLibrarySaver.SaveError.notAuthorized {
                saveError = String(localized: "写真ライブラリへのアクセスが許可されていません。設定アプリから許可してください。")
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}

// Nonisolated helper to avoid @MainActor leaking into PHPhotoLibrary's @Sendable closure
private enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            String(localized: "写真ライブラリへのアクセスが許可されていません")
        }
    }

    static func save(videoAt url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.notAuthorized
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

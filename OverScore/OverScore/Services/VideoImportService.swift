import Foundation
import AVFoundation

struct VideoImportService {
    /// Documents/Videos/ ディレクトリ。存在しなければ作成する。
    static func videosDirectory() throws -> URL {
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videosDir = documentsDir.appendingPathComponent("Videos", isDirectory: true)

        if !fileManager.fileExists(atPath: videosDir.path) {
            try fileManager.createDirectory(at: videosDir, withIntermediateDirectories: true)
        }
        return videosDir
    }

    /// Documents/Videos/ 内の新しい保存先URLを作る。
    static func makeSandboxURL(pathExtension: String) throws -> URL {
        let fileName = pathExtension.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(pathExtension)"
        return try videosDirectory().appendingPathComponent(fileName)
    }

    /// 受け取ったファイルを保存先へ引き取る。
    ///
    /// `canMove` が true のときだけ move を試す。同一ボリュームなら move は
    /// メタデータ操作だけで済むため、数GBの動画でも実データのコピーが発生しない。
    /// ボリュームをまたぐ場合は move が失敗するので copy にフォールバックする。
    ///
    /// `canMove` には `ReceivedTransferredFile.isOriginalFile` の否定を渡すこと。
    /// isOriginalFile が true のファイルは破棄用の複製ではなくユーザーの元ファイルであり、
    /// move するとユーザーの動画そのものを消してしまう。
    static func adoptFile(at sourceURL: URL, to destinationURL: URL, canMove: Bool) throws {
        let fileManager = FileManager.default
        if canMove {
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
                return
            } catch {
                // ボリュームをまたぐ場合など。複製にフォールバックする
            }
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    /// ユーザーの元ファイルを Documents/Videos/ に複製する。
    /// Files.app 経由のように元ファイルを残す必要がある経路で使う。
    static func copyToSandbox(from sourceURL: URL) async throws -> URL {
        let destinationURL = try makeSandboxURL(pathExtension: sourceURL.pathExtension)

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    static func creationDate(for url: URL) async -> Date? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let asset = AVURLAsset(url: url)
        if let items = try? await asset.load(.metadata) {
            if let item = items.first(where: { $0.commonKey == .commonKeyCreationDate }),
               let dateValue = try? await item.load(.value) {
                if let date = dateValue as? Date {
                    return date
                }
                if let str = try? await item.load(.stringValue),
                   let date = ISO8601DateFormatter().date(from: str) {
                    return date
                }
            }
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    static func deleteVideo(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    struct VideoInfo {
        let dimensions: CGSize
        let frameRate: Float
        let fileSize: Int64?
    }

    /// 動画ファイルから表示用のメタ情報（補正済み解像度・フレームレート）を取得する。
    /// フレームレートはエクスポート時に使う値と揃えるため VideoCompositionBuilder の検出ロジックを共用する。
    static func videoInfo(for url: URL) async -> VideoInfo? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let frameDuration = try await VideoCompositionBuilder.detectFrameDuration(of: track, in: asset)
            let frameRate: Float = frameDuration.seconds > 0 ? Float(1.0 / frameDuration.seconds) : 0
            let dimensions = VideoCompositionBuilder.correctedSize(naturalSize: naturalSize, transform: transform)
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            return VideoInfo(dimensions: dimensions, frameRate: frameRate, fileSize: fileSize)
        } catch {
            return nil
        }
    }

    /// Documents/Videos/ 内の孤立ファイル（どのMatchからも参照されていない）を削除
    static func cleanupOrphanedVideos(referencedURLs: Set<URL>) {
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videosDir = documentsDir.appendingPathComponent("Videos", isDirectory: true)

        guard let files = try? fileManager.contentsOfDirectory(
            at: videosDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files {
            if !referencedURLs.contains(file) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    /// /tmp/ 内の OverScore が作った一時ファイルを削除する。
    ///
    /// 対象は2種類:
    /// - エクスポート出力 `OverScore_<UUID>.mp4`
    /// - 旧バージョンの写真ライブラリ取り込みが残した `<UUID>.<動画拡張子>`
    ///   （取り込み時に一時ファイルへ複製したまま削除しておらず、
    ///    動画1本ぶんのフルコピーが端末に残り続けていた。
    ///    現在は Documents/Videos/ へ直接取り込むため新たには発生しない）
    static func cleanupTempExportFiles() {
        let fileManager = FileManager.default
        let tmpDir = fileManager.temporaryDirectory

        guard let files = try? fileManager.contentsOfDirectory(
            at: tmpDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where isRemovableTempFile(file) {
            try? fileManager.removeItem(at: file)
        }
    }

    /// 旧バージョンの取り込みが残した一時動画ファイルの拡張子。
    private static let importedVideoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    /// OverScore が作った一時ファイルかどうか。
    /// 取り込み一時ファイルはファイル名がUUIDのものだけに限定し、
    /// 他のアプリやシステムが /tmp/ に置いたファイルを巻き込まないようにする。
    static func isRemovableTempFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix("OverScore_") && url.pathExtension == "mp4" {
            return true
        }
        guard importedVideoExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }
}

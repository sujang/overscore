import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import os

struct VideoEntry: Identifiable {
    let id = UUID()
    let url: URL
    var originalFileName: String?
    var thumbnail: UIImage?
    var creationDate: Date?
    var dimensions: CGSize?
    var frameRate: Float?
}

struct SportSelectView: View {
    @Environment(Router.self) private var router
    @State private var selected: SportType = .soccer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("スポーツを選ぶ")
                        .font(.title2.bold())
                    Text("選ぶだけでスコアボードを自動設定します")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(SportType.allCases) { sport in
                        sportCard(sport)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("かんたんスタート")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                router.navigate(to: .matchSetup(selected))
            } label: {
                Text("次へ")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func sportCard(_ sport: SportType) -> some View {
        Button {
            selected = sport
        } label: {
            VStack(spacing: 8) {
                Text(sport.emoji)
                    .font(.system(size: 32))
                Text(sport.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected == sport ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected == sport ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MatchSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Router.self) private var router

    let sportType: SportType

    @State private var homeTeamName = ""
    @State private var awayTeamName = ""
    @State private var matchInfo = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var videoEntries: [VideoEntry] = []
    @State private var isImporting = false
    @State private var importFraction: Double?
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    @State private var createdMatch: Match?
    @State private var thumbnail: UIImage?
    @State private var setupVideoAspectRatio: CGFloat = 16.0 / 9.0
    @State private var videoOnlyMerge = false

    private var canProceed: Bool {
        !homeTeamName.trimmingCharacters(in: .whitespaces).isEmpty
        && !awayTeamName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Text(sportType.emoji)
                    Text(sportType.displayName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("選択中のスポーツ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("チーム名") {
                TextField("ホームチーム", text: $homeTeamName)
                    .textInputAutocapitalization(.words)
                TextField("アウェイチーム", text: $awayTeamName)
                    .textInputAutocapitalization(.words)
            }

            Section {
                TextField("例: 第100回全国高校サッカー選手権 決勝", text: $matchInfo)
            } header: {
                Text("試合情報")
            } footer: {
                Text("大会名や日程など、スコアボードに表示する情報")
            }

            Section {
                if !videoEntries.isEmpty {
                    ForEach(videoEntries) { entry in
                        HStack(spacing: 12) {
                            if let thumb = entry.thumbnail {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 45)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Rectangle()
                                    .fill(.quaternary)
                                    .frame(width: 80, height: 45)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay {
                                        Image(systemName: "video")
                                            .foregroundStyle(.secondary)
                                    }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.originalFileName ?? entry.url.lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let date = entry.creationDate {
                                    Text(date, format: .dateTime.year().month().day().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onMove { from, to in
                        videoEntries.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { offsets in
                        videoEntries.remove(atOffsets: offsets)
                    }
                }

                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 10,
                    matching: .videos,
                    preferredItemEncoding: .current
                ) {
                    Label(
                        isImporting ? String(localized: "読み込み中...") : String(localized: "写真ライブラリから追加"),
                        systemImage: "photo.on.rectangle"
                    )
                }
                .disabled(isImporting)

                Button {
                    showFileImporter = true
                } label: {
                    Label(
                        "ファイルから追加",
                        systemImage: "folder"
                    )
                }
                .disabled(isImporting)

                if isImporting {
                    VideoImportProgressView(fraction: importFraction)
                }
            } header: {
                Text("試合動画")
            } footer: {
                if videoEntries.count > 1 {
                    Text("ドラッグで並び替え、スワイプで削除できます。動画は上から順に結合されます。")
                }
            }

            Section {
                Toggle(isOn: $videoOnlyMerge) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("動画のみ結合")
                        Text("スコアボードを付けずに動画を結合します")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                Button {
                    createMatch()
                } label: {
                    HStack {
                        Spacer()
                        Text(videoOnlyMerge ? String(localized: "次へ: 確認画面") : String(localized: "次へ: スコアボード設定"))
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(!canProceed || isImporting)
            }
        }
        .navigationTitle("新規試合")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await importVideos(from: newItems)
                selectedItems = []
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await importVideosFromFiles(urls: urls)
                }
            case .failure(let error):
                errorMessage = String(localized: "ファイルの読み込みに失敗: \(error.localizedDescription)")
            }
        }
        .sheet(item: $createdMatch) { match in
            ScoreboardStyleSheet(
                match: match,
                thumbnail: thumbnail,
                videoAspectRatio: setupVideoAspectRatio
            ) {
                router.navigate(to: .scoreEditor(match))
            }
        }
    }

    private func importVideos(from items: [PhotosPickerItem]) async {
        isImporting = true
        errorMessage = nil

        for item in items {
            do {
                importFraction = nil
                guard let movie = try await VideoTransferable.load(
                    from: item,
                    onProgress: { importFraction = $0 }
                ) else {
                    continue
                }

                // VideoTransferable が Documents/Videos/ へ直接取り込み済み
                let originalName = movie.originalFileName
                let sandboxURL = movie.url
                let creationDate = await VideoImportService.creationDate(for: sandboxURL)
                let thumb = await ThumbnailGenerator.generate(for: sandboxURL)
                await MainActor.run {
                    videoEntries.append(VideoEntry(url: sandboxURL, originalFileName: originalName, thumbnail: thumb, creationDate: creationDate))
                }
            } catch {
                await MainActor.run {
                    errorMessage = String(localized: "動画のインポートに失敗: \(error.localizedDescription)")
                }
            }
        }

        await MainActor.run {
            isImporting = false
        }
    }

    private func importVideosFromFiles(urls: [URL]) async {
        isImporting = true
        errorMessage = nil

        for url in urls {
            do {
                let originalName = url.lastPathComponent
                let creationDate = await VideoImportService.creationDate(for: url)
                let sandboxURL = try await VideoImportService.copyToSandbox(from: url)
                let thumb = await ThumbnailGenerator.generate(for: sandboxURL)
                await MainActor.run {
                    videoEntries.append(VideoEntry(url: sandboxURL, originalFileName: originalName, thumbnail: thumb, creationDate: creationDate))
                }
            } catch {
                await MainActor.run {
                    errorMessage = "動画のインポートに失敗: \(error.localizedDescription)"
                }
            }
        }

        await MainActor.run {
            isImporting = false
        }
    }

    private func createMatch() {
        let match = Match(
            homeTeamName: homeTeamName.trimmingCharacters(in: .whitespaces),
            awayTeamName: awayTeamName.trimmingCharacters(in: .whitespaces)
        )
        let trimmedInfo = matchInfo.trimmingCharacters(in: .whitespaces)
        if !trimmedInfo.isEmpty {
            match.matchInfo = trimmedInfo
        }
        match.videoURLs = videoEntries.map(\.url)
        match.sportType = sportType
        var style = match.scoreboardStyle
        sportType.applyPreset(to: &style)
        match.scoreboardStyle = style
        modelContext.insert(match)

        if videoOnlyMerge {
            match.skipOverlay = true
            router.navigate(to: .matchDetail(match))
        } else {
            thumbnail = videoEntries.first?.thumbnail
            if let size = videoEntries.first?.thumbnail?.size, size.width > 0 {
                setupVideoAspectRatio = size.width / size.height
            }
            createdMatch = match
        }
    }
}

/// 写真ライブラリから受け取った動画。Documents/Videos/ へ直接取り込み済み。
/// PhotosPicker 側で `preferredItemEncoding: .current` を指定し、HEVC→H.264 のトランスコードを避けること。
struct VideoTransferable {
    /// Documents/Videos/ 内の取り込み先
    let url: URL
    let originalFileName: String

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OverScore",
        category: "VideoImport"
    )

    /// 写真ライブラリの動画を、元の形式のまま Documents/Videos/ へ取り込む。
    ///
    /// `.movie` だけを要求すると、元が MP4 でも写真ライブラリ側で QuickTime として
    /// 書き出し直されることがあり、数GBの動画で取り込みが極端に遅くなる。
    /// そのためアイテムが最初に挙げる形式（元の形式）を明示して受け取る。
    ///
    /// - Parameter onProgress: 写真ライブラリ側の書き出し進捗（0〜1）。
    ///   写真アプリで編集済みの動画などは受け取り前に作り直されるため数分かかることがある。
    static func load(
        from item: PhotosPickerItem,
        onProgress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws -> VideoTransferable? {
        let supportedTypes = item.supportedContentTypes
        let requestedType = supportedTypes.first { $0.conforms(to: .movie) } ?? .movie
        logger.notice("""
            supportedContentTypes=[\(supportedTypes.map(\.identifier).joined(separator: ", "), privacy: .public)] \
            requested=\(requestedType.identifier, privacy: .public)
            """)

        let clock = ContinuousClock()
        let start = clock.now
        let video: VideoTransferable?
        if requestedType == .mpeg4Movie {
            video = try await loadTransferable(ReceivedVideo<MPEG4Movie>.self, from: item, onProgress: onProgress)?.video
        } else if requestedType == .quickTimeMovie {
            video = try await loadTransferable(ReceivedVideo<QuickTimeMovie>.self, from: item, onProgress: onProgress)?.video
        } else {
            video = try await loadTransferable(ReceivedVideo<AnyMovie>.self, from: item, onProgress: onProgress)?.video
        }
        logger.notice("loadTransferable elapsed=\(start.duration(to: clock.now).description, privacy: .public)")

        if let video {
            await logFileDetails(of: video.url)
        }
        return video
    }

    /// 進捗を通知しながら loadTransferable する。
    /// async 版の loadTransferable は Progress を返さないため、completionHandler 版を包む。
    private static func loadTransferable<T: Transferable>(
        _ type: T.Type,
        from item: PhotosPickerItem,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws -> T? {
        let observationBox = ProgressObservationBox()
        defer { observationBox.observation?.invalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            let progress = item.loadTransferable(type: type) { result in
                continuation.resume(with: result)
            }
            observationBox.observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in onProgress(fraction) }
            }
        }
    }

    private final class ProgressObservationBox {
        var observation: NSKeyValueObservation?
    }

    /// 受け取ったファイルを Documents/Videos/ へ引き取る。
    /// received.file はクロージャを抜けると破棄されるため、importing の中で呼ぶこと。
    fileprivate static func adopt(_ received: ReceivedTransferredFile) throws -> VideoTransferable {
        let fileSize = (try? received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        logger.notice("""
            received file=\(received.file.lastPathComponent, privacy: .public) \
            size=\(fileSize, privacy: .public) isOriginalFile=\(received.isOriginalFile, privacy: .public)
            """)

        let destination = try VideoImportService.makeSandboxURL(
            pathExtension: received.file.pathExtension
        )
        // isOriginalFile のときは破棄用の複製ではなくユーザーの元ファイルなので move しない
        try VideoImportService.adoptFile(
            at: received.file,
            to: destination,
            canMove: !received.isOriginalFile
        )
        return VideoTransferable(url: destination, originalFileName: received.file.lastPathComponent)
    }

    /// 取り込んだファイルのコーデック・解像度を記録する（変換されたかの調査用）
    private static func logFileDetails(of url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (formatDescriptions, naturalSize) = try? await track.load(.formatDescriptions, .naturalSize)
        else {
            logger.error("imported file has no readable video track")
            return
        }
        let codecs = formatDescriptions.map { fourCCString(CMFormatDescriptionGetMediaSubType($0)) }
        logger.notice("""
            imported codec=\(codecs.joined(separator: ","), privacy: .public) \
            size=\(Int(naturalSize.width), privacy: .public)x\(Int(naturalSize.height), privacy: .public)
            """)
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? String(code)
    }
}

/// 写真ライブラリから要求する動画形式
protocol PickedMovieType {
    static var contentType: UTType { get }
}

enum MPEG4Movie: PickedMovieType { static let contentType = UTType.mpeg4Movie }
enum QuickTimeMovie: PickedMovieType { static let contentType = UTType.quickTimeMovie }
enum AnyMovie: PickedMovieType { static let contentType = UTType.movie }

/// 指定形式で写真ライブラリから受け取るための Transferable
private struct ReceivedVideo<MovieType: PickedMovieType>: Transferable {
    let video: VideoTransferable

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: MovieType.contentType) { received in
            Self(video: try VideoTransferable.adopt(received))
        }
    }
}

/// 動画取り込み中の表示。写真ライブラリが進捗を報告している間はパーセントを表示する。
struct VideoImportProgressView: View {
    /// 0〜1。まだ進捗が届いていなければ nil
    let fraction: Double?

    var body: some View {
        if let fraction, fraction > 0, fraction < 1 {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction)
                Text("動画を読み込み中... \(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else {
            HStack(spacing: 8) {
                ProgressView()
                Text("動画を読み込み中...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

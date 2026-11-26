import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct VideoManagementSheet: View {
    @Bindable var match: Match
    @Environment(\.dismiss) private var dismiss

    @State private var videoEntries: [VideoEntry] = []
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importFraction: Double?
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    @State private var didLoad = false
    @State private var showDiscardConfirm = false

    private var hasUnsavedChanges: Bool {
        didLoad && videoEntries.map(\.url) != match.videoURLs
    }

    var body: some View {
        NavigationStack {
            List {
                if !videoEntries.isEmpty {
                    Section {
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
                                    if let info = entry.infoText {
                                        Text(info)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
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
                    } header: {
                        Text("動画一覧")
                    } footer: {
                        if videoEntries.count > 1 {
                            Text("ドラッグで並び替え、スワイプで削除できます。動画は上から順に結合されます。")
                        }
                    }
                }

                Section {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 10,
                        matching: .videos,
                        preferredItemEncoding: .current
                    ) {
                        Label(
                            isImporting ? "読み込み中..." : "写真ライブラリから追加",
                            systemImage: "photo.on.rectangle"
                        )
                    }
                    .disabled(isImporting)

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("ファイルから追加", systemImage: "folder")
                    }
                    .disabled(isImporting)

                    if isImporting {
                        VideoImportProgressView(fraction: importFraction)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("動画管理")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasUnsavedChanges || isImporting)
            .confirmationDialog(
                "変更を破棄しますか？",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("変更を破棄", role: .destructive) { dismiss() }
                Button("編集を続ける", role: .cancel) {}
            } message: {
                Text("保存していない変更は失われます。")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if hasUnsavedChanges {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        match.videoURLs = videoEntries.map(\.url)
                        dismiss()
                    }
                    .disabled(isImporting)
                }
            }
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
                    Task { await importVideosFromFiles(urls: urls) }
                case .failure(let error):
                    errorMessage = String(localized: "ファイルの読み込みに失敗: \(error.localizedDescription)")
                }
            }
        }
        .task {
            await loadExistingVideos()
        }
    }

    // MARK: - Load existing videos

    private func loadExistingVideos() async {
        var entries: [VideoEntry] = []
        for url in match.videoURLs {
            let thumb = await ThumbnailGenerator.generate(for: url)
            let date = await VideoImportService.creationDate(for: url)
            let info = await VideoImportService.videoInfo(for: url)
            entries.append(VideoEntry(
                url: url,
                originalFileName: url.lastPathComponent,
                thumbnail: thumb,
                creationDate: date,
                dimensions: info?.dimensions,
                frameRate: info?.frameRate,
                fileSize: info?.fileSize
            ))
        }
        videoEntries = entries
        didLoad = true
    }

    // MARK: - Import from Photos Library

    private func importVideos(from items: [PhotosPickerItem]) async {
        // 取り込み中にロックされると処理が中断・アプリが終了されるため、完了まで実行を継続させる
        let activity = LongRunningActivity.begin(
            name: "OverScoreImportPhotos",
            title: String(localized: "動画を読み込み中...")
        )
        defer { activity.end() }
        isImporting = true
        errorMessage = nil

        for (index, item) in items.enumerated() {
            // 実行猶予がなくなり中断した後は、残りの動画の転送を始めない
            if activity.wasInterrupted { break }
            activity.beginStage(upTo: Double(index + 1) / Double(items.count))
            defer {
                activity.setCancellable(nil)
                activity.updateProgress(Double(index + 1) / Double(items.count))
            }
            do {
                importFraction = nil
                guard let movie = try await VideoTransferable.load(
                    from: item,
                    onStart: { activity.setCancellable($0) },
                    onProgress: { fraction in
                        importFraction = fraction
                        activity.updateProgress((Double(index) + fraction) / Double(items.count))
                    }
                ) else { continue }
                // VideoTransferable が Documents/Videos/ へ直接取り込み済み
                let originalName = movie.originalFileName
                let sandboxURL = movie.url
                let creationDate = await VideoImportService.creationDate(for: sandboxURL)
                let thumb = await ThumbnailGenerator.generate(for: sandboxURL)
                let info = await VideoImportService.videoInfo(for: sandboxURL)
                await MainActor.run {
                    videoEntries.append(VideoEntry(
                        url: sandboxURL,
                        originalFileName: originalName,
                        thumbnail: thumb,
                        creationDate: creationDate,
                        dimensions: info?.dimensions,
                        frameRate: info?.frameRate,
                        fileSize: info?.fileSize
                    ))
                }
            } catch {
                await MainActor.run {
                    errorMessage = activity.wasInterrupted
                        ? String(localized: "画面がロックされたため、動画の読み込みを中断しました。もう一度追加してください")
                        : String(localized: "動画のインポートに失敗: \(error.localizedDescription)")
                }
            }
        }

        await MainActor.run { isImporting = false }
    }

    // MARK: - Import from Files

    private func importVideosFromFiles(urls: [URL]) async {
        // 取り込み中にロックされると処理が中断・アプリが終了されるため、完了まで実行を継続させる
        let activity = LongRunningActivity.begin(
            name: "OverScoreImportFiles",
            title: String(localized: "動画を読み込み中...")
        )
        defer { activity.end() }
        isImporting = true
        errorMessage = nil

        for (index, url) in urls.enumerated() {
            activity.beginStage(upTo: Double(index + 1) / Double(urls.count))
            defer { activity.updateProgress(Double(index + 1) / Double(urls.count)) }
            do {
                let originalName = url.lastPathComponent
                let creationDate = await VideoImportService.creationDate(for: url)
                let sandboxURL = try await VideoImportService.copyToSandbox(from: url)
                let thumb = await ThumbnailGenerator.generate(for: sandboxURL)
                let info = await VideoImportService.videoInfo(for: sandboxURL)
                await MainActor.run {
                    videoEntries.append(VideoEntry(
                        url: sandboxURL,
                        originalFileName: originalName,
                        thumbnail: thumb,
                        creationDate: creationDate,
                        dimensions: info?.dimensions,
                        frameRate: info?.frameRate,
                        fileSize: info?.fileSize
                    ))
                }
            } catch {
                await MainActor.run {
                    errorMessage = String(localized: "動画のインポートに失敗: \(error.localizedDescription)")
                }
            }
        }

        await MainActor.run { isImporting = false }
    }
}

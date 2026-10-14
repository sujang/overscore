import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

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
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("動画を読み込み中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
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

/// 写真ライブラリから受け取った動画。受け取り時に Documents/Videos/ へ直接コピーする。
/// PhotosPicker 側で `preferredItemEncoding: .current` を指定し、HEVC→H.264 のトランスコードを避けること。
struct VideoTransferable: Transferable {
    /// Documents/Videos/ 内のコピー先
    let url: URL
    let originalFileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // 一時ファイルを経由せず Documents/Videos/ へ直接取り込む。
            // 以前は tmp に複製してから copyToSandbox でもう一度複製しており、
            // 数GBの試合動画をフルコピー2回ぶん余計に書いていた。
            // received.file はこのクロージャを抜けると破棄されるため、ここで引き取る。
            let destination = try VideoImportService.makeSandboxURL(
                pathExtension: received.file.pathExtension
            )
            // isOriginalFile のときは破棄用の複製ではなくユーザーの元ファイルなので move しない
            try VideoImportService.adoptFile(
                at: received.file,
                to: destination,
                canMove: !received.isOriginalFile
            )
            return Self(url: destination, originalFileName: received.file.lastPathComponent)
        }
    }
}

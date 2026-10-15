import SwiftUI
import AVKit

struct ExportView: View {
    @Environment(Router.self) private var router
    let match: Match
    @State private var viewModel: ExportViewModel?
    @State private var player: AVPlayer?
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0
    @State private var hasStarted = false

    var body: some View {
        Group {
            if let vm = viewModel {
                if hasStarted {
                    exportContent(vm: vm)
                } else {
                    confirmationView(vm: vm)
                }
            } else {
                ProgressView("準備中...")
                    .task { prepareViewModel() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("エクスポート")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    viewModel?.cleanupExportedFile()
                    router.popToRoot()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("一覧")
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            if let url = match.videoURLs.first,
               let size = await ThumbnailGenerator.videoSize(for: url) {
                videoAspectRatio = size.width / size.height
            }
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func confirmationView(vm: ExportViewModel) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "square.and.arrow.up.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("この内容でエクスポートします")
                .font(.headline)

            VStack(spacing: 10) {
                summaryRow(label: String(localized: "対戦"), value: "\(match.homeTeamName) \(match.homeScore) - \(match.awayScore) \(match.awayTeamName)")
                Divider()
                summaryRow(label: String(localized: "動画"), value: String(localized: "\(match.videoURLs.count)本"))
                Divider()
                summaryRow(label: String(localized: "スコアボード"), value: match.skipOverlay ? String(localized: "なし（動画のみ結合）") : String(localized: "あり"))
                Divider()
                outputPreviewRows(vm: vm)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .frame(maxWidth: 400)

            Button {
                hasStarted = true
                vm.startExport()
            } label: {
                Label("エクスポート開始", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: 400)

            Spacer()
        }
        .padding()
        .task { await vm.loadOutputPreview() }
    }

    /// エクスポート後の動画の見込み（解像度・FPS・予想サイズ）
    @ViewBuilder
    private func outputPreviewRows(vm: ExportViewModel) -> some View {
        let preview = vm.outputPreview
        let placeholder = vm.isLoadingOutputPreview ? String(localized: "計算中...") : "—"

        summaryRow(
            label: String(localized: "解像度"),
            value: preview.map { "\(Int($0.renderSize.width))×\(Int($0.renderSize.height))" } ?? placeholder
        )
        Divider()
        summaryRow(
            label: String(localized: "フレームレート"),
            value: preview.map { "\($0.frameRate.formatted(.number.precision(.fractionLength(0...2)))) fps" } ?? placeholder
        )
        Divider()
        summaryRow(
            label: String(localized: "ファイルサイズ（予想）"),
            value: preview.map { preview in
                preview.estimatedFileSize.map {
                    String(localized: "約 \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))")
                } ?? "—"
            } ?? placeholder
        )
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func exportContent(vm: ExportViewModel) -> some View {
        VStack(spacing: 16) {
            if vm.isExporting {
                exportingView(vm: vm)
            } else if let url = vm.exportedURL {
                completedView(vm: vm, url: url)
            } else if vm.isCancelledByUser {
                cancelledView()
            } else if let error = vm.exportError {
                errorView(error: error)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(
            get: { vm.showShareSheet },
            set: { vm.showShareSheet = $0 }
        )) {
            if let url = vm.exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportingView(vm: ExportViewModel) -> some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView(value: vm.progress) {
                // 進捗0%の間はコンポジション構築中（進捗を取得できない段階）
                Text(vm.progress == 0 ? String(localized: "エクスポートを準備中...") : String(localized: "エクスポート中..."))
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(vm.progress * 100))%")
                    .monospacedDigit()
            }
            .progressViewStyle(.linear)
            .frame(maxWidth: 300)

            Text("\(match.homeTeamName) \(match.homeScore) - \(match.awayScore) \(match.awayTeamName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("キャンセル", role: .destructive) {
                vm.cancelExport()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private func completedView(vm: ExportViewModel, url: URL) -> some View {
        VStack(spacing: 16) {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(videoAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Label("エクスポート完了", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            HStack(spacing: 16) {
                Button {
                    vm.showShareSheet = true
                } label: {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    vm.saveToPhotos()
                } label: {
                    Label(
                        vm.savedToPhotos ? String(localized: "保存済み") : String(localized: "写真に保存"),
                        systemImage: vm.savedToPhotos ? "checkmark" : "photo.on.rectangle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(vm.savedToPhotos)
            }
            .frame(maxWidth: 400)

            if let saveError = vm.saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            player = AVPlayer(url: url)
        }
    }

    /// ユーザーによるキャンセル後の表示（失敗ではないため警告表現を使わない）
    private func cancelledView() -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "xmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("エクスポートをキャンセルしました")
                .font(.headline)

            Button("再開する") {
                viewModel?.startExport()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    private func errorView(error: Error) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text("エクスポートに失敗しました")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("再試行") {
                viewModel?.startExport()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    private func prepareViewModel() {
        guard viewModel == nil else { return }
        viewModel = ExportViewModel(match: match)
    }
}

import SwiftUI
import SwiftData

struct MatchListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Router.self) private var router
    @Query(sort: \Match.createdAt, order: .reverse) private var matches: [Match]
    @State private var showDeleteConfirmation = false
    @State private var matchToDelete: Match?
    @State private var showSettings = false
    /// 入力途中の新規試合（動画の取り込み中にアプリが終了した場合などに残る）
    @State private var draft: MatchDraft?
    @State private var showDiscardDraftConfirmation = false

    var body: some View {
        Group {
            if matches.isEmpty {
                emptyStateView
            } else {
                matchList
            }
        }
        .safeAreaInset(edge: .top) {
            if let draft {
                draftBanner(draft)
            }
        }
        .onAppear {
            draft = MatchDraftStore.load()
        }
        .navigationTitle("OverScore")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("設定")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.navigate(to: .sportSelect)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新しい試合")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("試合を削除", isPresented: $showDeleteConfirmation) {
            Button("削除", role: .destructive) {
                if let match = matchToDelete {
                    deleteMatch(match)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この試合データを削除しますか？元に戻すことはできません。")
        }
        .alert("入力途中の試合を破棄", isPresented: $showDiscardDraftConfirmation) {
            Button("破棄", role: .destructive) {
                MatchDraftStore.discard()
                draft = nil
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("入力した内容と読み込み済みの動画を削除します。元に戻すことはできません。")
        }
    }

    private func draftBanner(_ draft: MatchDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("入力途中の試合があります", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
            Text(draftSummary(draft))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Button {
                    router.navigate(to: .resumeMatchSetup)
                } label: {
                    Text("続きから")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    showDiscardDraftConfirmation = true
                } label: {
                    Text("破棄")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
        .padding(.top, 8)
        .background(.bar)
    }

    /// 例: "⚽️ FC東京 vs FC大阪 · 動画 2本"
    private func draftSummary(_ draft: MatchDraft) -> String {
        let unnamed = String(localized: "未入力")
        let home = draft.homeTeamName.trimmingCharacters(in: .whitespaces)
        let away = draft.awayTeamName.trimmingCharacters(in: .whitespaces)
        var parts = ["\(draft.sportType.emoji) \(home.isEmpty ? unnamed : home) vs \(away.isEmpty ? unnamed : away)"]
        if !draft.videos.isEmpty {
            parts.append(String(localized: "動画 \(draft.videos.count)本"))
        }
        return parts.joined(separator: " · ")
    }

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            ContentUnavailableView {
                Label("試合がありません", systemImage: "sportscourt")
            } description: {
                Text("下のボタンから試合を作成しましょう")
            }
            .frame(maxHeight: .infinity)

            Button {
                router.navigate(to: .sportSelect)
            } label: {
                Label("新しい試合", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private var matchList: some View {
        List {
            ForEach(matches) { match in
                Button {
                    router.navigate(to: .matchDetail(match))
                } label: {
                    MatchRowView(match: match)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        matchToDelete = match
                        showDeleteConfirmation = true
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            Button {
                router.navigate(to: .sportSelect)
            } label: {
                Label("新しい試合", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
    }

    private func deleteMatch(_ match: Match) {
        for url in match.videoURLs {
            VideoImportService.deleteVideo(at: url)
        }
        modelContext.delete(match)
        matchToDelete = nil
    }
}

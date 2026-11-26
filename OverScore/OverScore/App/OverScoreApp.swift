import SwiftUI
import SwiftData

@main
struct OverScoreApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Match.self, ScoreEvent.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        cleanupOnLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }

    private func cleanupOnLaunch() {
        // エクスポート一時ファイルを削除
        VideoImportService.cleanupTempExportFiles()

        // 孤立した動画ファイルを削除
        let context = ModelContext(container)
        let referencedURLs = collectReferencedVideoURLs(context: context)
        VideoImportService.cleanupOrphanedVideos(referencedURLs: referencedURLs)

        // 既存の試合からチームプリセットを作成（初回のみ）
        TeamPresetStore.backfillIfNeeded(from: (try? context.fetch(FetchDescriptor<Match>())) ?? [])
    }

    private func collectReferencedVideoURLs(context: ModelContext) -> Set<URL> {
        var urls = Set<URL>()
        do {
            let matches = try context.fetch(FetchDescriptor<Match>())
            for match in matches {
                for url in match.videoURLs {
                    urls.insert(url)
                }
            }
        } catch {
            // フェッチ失敗時は安全のため何も削除しない
        }
        // 入力途中の新規試合（下書き）が取り込んだ動画も残す
        if let draft = MatchDraftStore.load() {
            urls.formUnion(draft.videoURLs)
        }
        return urls
    }
}

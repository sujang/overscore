import Foundation

/// 新規試合画面の入力途中の内容。
///
/// 動画の取り込み中にアプリが終了しても入力内容と取り込み済みの動画を失わないよう、
/// 入力のたびに保存し、次回起動時に試合一覧から復元できるようにする。
/// 画面を通常の操作で離れたとき（試合の作成・戻る）は破棄する。
struct MatchDraft: Codable, Equatable {
    struct Video: Codable, Equatable {
        /// Documents/Videos/ 内のファイル名。
        /// アプリの更新などでコンテナのパスが変わるため、フルパスではなくファイル名で持つ。
        var fileName: String
        var originalFileName: String?
    }

    var sportType: SportType
    var homeTeamName: String
    var awayTeamName: String
    var matchInfo: String
    /// 過去のチームから選んだホームチーム（選択後にチーム名を変えた場合は適用しない）
    var presetName: String?
    var presetColorHex: String?
    var videoOnlyMerge: Bool
    var videos: [Video]

    /// 保存する価値のある入力がないか
    var isEmpty: Bool {
        homeTeamName.trimmingCharacters(in: .whitespaces).isEmpty
        && awayTeamName.trimmingCharacters(in: .whitespaces).isEmpty
        && matchInfo.trimmingCharacters(in: .whitespaces).isEmpty
        && videos.isEmpty
    }

    /// 動画ファイルの現在のURL
    var videoURLs: [URL] {
        guard let directory = try? VideoImportService.videosDirectory() else { return [] }
        return videos.map { directory.appendingPathComponent($0.fileName) }
    }
}

/// MatchDraft の永続化。強制終了されても残るよう、変更のたびに UserDefaults へ書き込む。
enum MatchDraftStore {
    private static let key = "matchDraft"

    static func load() -> MatchDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MatchDraft.self, from: data)
    }

    /// 保存する。入力が空なら下書き自体を消す。
    static func save(_ draft: MatchDraft) {
        guard !draft.isEmpty, let data = try? JSONEncoder().encode(draft) else {
            clear()
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 下書きを消す。動画ファイルは残す（作成した試合が引き継ぐ、または起動時の掃除で消える）。
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// 下書きと、取り込み済みの動画ファイルを削除する。
    static func discard() {
        if let draft = load() {
            for url in draft.videoURLs {
                VideoImportService.deleteVideo(at: url)
            }
        }
        clear()
    }
}

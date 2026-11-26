import Foundation

/// 過去に入力した自チーム（ホーム）の名前とチームカラー。新規試合でプリセットとして選択できる。
struct TeamPreset: Codable, Identifiable, Equatable {
    var name: String
    /// "#RRGGBB" 形式。nil=チームカラー未設定
    var colorHex: String?
    var lastUsedAt: Date

    var id: String { name }
}

/// TeamPreset の永続化。試合を削除してもプリセットが残るよう、Match とは別に UserDefaults へ保存する。
enum TeamPresetStore {
    private static let presetsKey = "teamPresets"
    private static let backfilledKey = "teamPresetsBackfilled"
    private static let maxCount = 30

    /// 最近使った順のプリセット一覧
    static func load() -> [TeamPreset] {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let presets = try? JSONDecoder().decode([TeamPreset].self, from: data) else {
            return []
        }
        return presets.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    /// チーム名をキーに登録・更新する。colorHex が nil のときは登録済みの色を維持する。
    static func record(name: String, colorHex: String?, usedAt: Date = Date()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var presets = load()
        let existing = presets.first { $0.name == trimmed }
        presets.removeAll { $0.name == trimmed }
        presets.append(TeamPreset(
            name: trimmed,
            colorHex: colorHex ?? existing?.colorHex,
            lastUsedAt: max(usedAt, existing?.lastUsedAt ?? .distantPast)
        ))
        save(presets)
    }

    static func remove(name: String) {
        save(load().filter { $0.name != name })
    }

    /// プリセット機能の導入前に作成された試合から、初回のみプリセットを作成する。
    static func backfillIfNeeded(from matches: @autoclosure () -> [Match]) {
        guard !UserDefaults.standard.bool(forKey: backfilledKey) else { return }
        for match in matches().sorted(by: { $0.createdAt < $1.createdAt }) {
            record(
                name: match.homeTeamName,
                colorHex: match.scoreboardStyle.homeTeamColorHex,
                usedAt: match.createdAt
            )
        }
        UserDefaults.standard.set(true, forKey: backfilledKey)
    }

    private static func save(_ presets: [TeamPreset]) {
        let kept = presets.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(maxCount)
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(kept)), forKey: presetsKey)
    }
}

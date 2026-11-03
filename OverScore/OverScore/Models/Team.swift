import Foundation

enum Team: String, Codable, CaseIterable, Identifiable {
    case home
    case away

    var id: String { rawValue }
}

/// 試合のスポーツ種別。選択するとスコアボードの既定設定が自動で切り替わる。
enum SportType: String, Codable, CaseIterable, Identifiable, Hashable {
    case soccer
    case basketball
    case volleyball
    case rugby

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .soccer: return String(localized: "サッカー")
        case .basketball: return String(localized: "バスケ")
        case .volleyball: return String(localized: "バレー")
        case .rugby: return String(localized: "ラグビー他")
        }
    }

    var emoji: String {
        switch self {
        case .soccer: return "⚽️"
        case .basketball: return "🏀"
        case .volleyball: return "🏐"
        case .rugby: return "🏉"
        }
    }

    var goalSystemImage: String {
        switch self {
        case .soccer: return "soccerball"
        case .basketball: return "basketball.fill"
        case .volleyball: return "volleyball.fill"
        case .rugby: return "sportscourt.fill"
        }
    }

    var goalButtonLabel: String {
        switch self {
        case .volleyball: return String(localized: "得点+")
        default: return String(localized: "ゴール+")
        }
    }

    /// この競技に合わせたスコアボードの既定表示設定を適用する
    func applyPreset(to style: inout ScoreboardStyle) {
        switch self {
        case .soccer:
            style.showSetCount = false
            style.showTimeouts = false
            style.showPenaltyTimer = false
        case .basketball:
            style.showSetCount = false
            style.showTimeouts = true
            style.showPenaltyTimer = false
        case .volleyball:
            style.showSetCount = true
            style.showTimeouts = true
            style.showPenaltyTimer = false
        case .rugby:
            style.showSetCount = false
            style.showTimeouts = false
            style.showPenaltyTimer = true
        }
    }

    /// セグメントのピリオドラベル候補（前半/後半、Qごと、セットごとなど）
    var periodPresets: [String] {
        switch self {
        case .soccer, .rugby:
            return [
                String(localized: "前半"),
                String(localized: "後半"),
                String(localized: "延前"),
                String(localized: "延後"),
                "PK"
            ]
        case .basketball:
            return ["Q1", "Q2", "Q3", "Q4", "OT"]
        case .volleyball:
            return [
                String(localized: "第1セット"),
                String(localized: "第2セット"),
                String(localized: "第3セット"),
                String(localized: "第4セット"),
                String(localized: "第5セット")
            ]
        }
    }
}

struct PKKick: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var team: Team
    var order: Int
    var isGoal: Bool
    var timestamp: TimeInterval
}

extension Array where Element == PKKick {
    /// PK戦の先攻チーム（動画内で最も早く蹴ったチーム）。キックが無い場合はホーム。
    var firstKickingTeam: Team {
        self.min { ($0.timestamp, $0.order) < ($1.timestamp, $1.order) }?.team ?? .home
    }
}

import SwiftUI

extension Color {
    static let scoreGold = Color(red: 1.0, green: 0.843, blue: 0.0)

    // MARK: - Hex Conversion

    /// "#RRGGBB" 形式の文字列から Color を生成
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexSanitized.hasPrefix("#") { hexSanitized.removeFirst() }
        guard hexSanitized.count == 6,
              let value = UInt64(hexSanitized, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Color -> "#RRGGBB" 形式の文字列
    var hexString: String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        if components.count >= 3 {
            r = components[0]; g = components[1]; b = components[2]
        } else {
            // グレースケール
            r = components[0]; g = components[0]; b = components[0]
        }
        return String(format: "#%02X%02X%02X",
                       Int(round(r * 255)),
                       Int(round(g * 255)),
                       Int(round(b * 255)))
    }

    /// 背景色として使ったとき、黒文字の方が読みやすいか（白・黄色などの明るい色）
    var prefersDarkForeground: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.7
    }

    static func scoreboardBackground(for theme: ScoreboardStyle.Theme) -> Color {
        switch theme {
        case .dark:
            return .black.opacity(0.7)
        case .light:
            return .white.opacity(0.8)
        case .broadcast:
            return Color(red: 0.1, green: 0.1, blue: 0.3).opacity(0.85)
        case .minimal:
            return .black.opacity(0.4)
        }
    }

    static func scoreboardText(for theme: ScoreboardStyle.Theme) -> Color {
        switch theme {
        case .dark, .broadcast, .minimal:
            return .white
        case .light:
            return .black
        }
    }

    static func scoreboardScore(for theme: ScoreboardStyle.Theme) -> Color {
        switch theme {
        case .dark, .broadcast:
            return .scoreGold
        case .light:
            return .blue
        case .minimal:
            return .white
        }
    }

    /// タイマーセクションの文字色（メインとの反転）
    static func scoreboardTimerText(for theme: ScoreboardStyle.Theme) -> Color {
        switch theme {
        case .dark, .broadcast, .minimal:
            return .black
        case .light:
            return .white
        }
    }
}

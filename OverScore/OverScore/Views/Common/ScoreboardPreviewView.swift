import SwiftUI

struct ScoreboardPreviewView: View {
    let homeTeamName: String
    let awayTeamName: String
    let homeScore: Int
    let awayScore: Int
    let style: ScoreboardStyle
    var currentPeriodLabel: String? = nil
    var matchInfo: String? = nil
    var pkKicks: [PKKick] = []
    var thumbnail: UIImage? = nil
    var videoAspectRatio: CGFloat = 16.0 / 9.0
    var timerShowPlusPrefix: Bool = false
    var timerDisplayColor: Color? = nil
    var penaltyTimers: [PenaltyTimer] = []
    var timeouts: [TimeoutEvent] = []
    var timerSegments: [TimerSegment] = []
    var currentVideoTime: TimeInterval = 0
    var homeSetCount: Int = 0
    var awaySetCount: Int = 0

    @State private var homeFlash: Bool = false
    @State private var awayFlash: Bool = false

    /// その時点で有効なホームチームアクセント色（セクション色オプション対応）
    private var effectiveHomeColor: Color {
        if style.useSegmentTeamColors,
           let hex = activeSegmentColorHex(team: .home),
           let c = Color(hex: hex) {
            return c
        }
        return style.homeTeamColor ?? Color.scoreboardScore(for: style.theme)
    }

    /// その時点で有効なアウェイチームアクセント色（セクション色オプション対応）
    private var effectiveAwayColor: Color {
        if style.useSegmentTeamColors,
           let hex = activeSegmentColorHex(team: .away),
           let c = Color(hex: hex) {
            return c
        }
        return style.awayTeamColor ?? Color.scoreboardScore(for: style.theme)
    }

    /// currentVideoTime 時点のアクティブセクションを参照し、そのセクションのチーム色 hex を返す。
    private func activeSegmentColorHex(team: Team) -> String? {
        guard !timerSegments.isEmpty else { return nil }
        var matched: TimerSegment? = nil
        for seg in timerSegments {
            guard let start = seg.effectiveStartTime else { continue }
            if start <= currentVideoTime { matched = seg }
        }
        return team == .home ? matched?.homeTeamColorHex : matched?.awayTeamColorHex
    }

    /// 得点時の背景強調色（テーマごと）
    private var flashColor: Color {
        switch style.theme {
        case .light:
            return .orange
        case .dark, .broadcast, .minimal:
            return Color(red: 1.0, green: 0.843, blue: 0.0)
        }
    }

    /// プレビューとエクスポートで共通の比率定数
    /// baseFontSize = containerWidth * baseRatio
    static let baseRatio: CGFloat = 0.044

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Video thumbnail or placeholder background
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.clear
                }

                // Scoreboard overlay + PK + Penalty timers
                if style.showTeamsSection {
                    VStack(alignment: .leading, spacing: geo.size.width * Self.baseRatio * 0.25) {
                        scoreboardContent(containerWidth: geo.size.width)

                        if currentPeriodLabel?.lowercased() == "pk", !pkKicks.isEmpty {
                            pkContent(containerWidth: geo.size.width)
                        }

                        penaltyTimerOverlay(containerWidth: geo.size.width)
                    }
                    .scaleEffect(style.scale, anchor: .topLeading)
                    .offset(
                        x: style.positionX * geo.size.width,
                        y: style.positionY * geo.size.height
                    )
                }

                // 試合情報（独立位置・スケール）
                if let info = matchInfo, !info.isEmpty {
                    matchInfoContent(info: info, containerWidth: geo.size.width)
                        .scaleEffect(style.matchInfoScale, anchor: .topLeading)
                        .offset(
                            x: style.matchInfoPositionX * geo.size.width,
                            y: style.matchInfoPositionY * geo.size.height
                        )
                }
            }
        }
        .contentShape(Rectangle())
        .aspectRatio(videoAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: homeScore) { _, _ in
            homeFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                homeFlash = false
            }
        }
        .onChange(of: awayScore) { _, _ in
            awayFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                awayFlash = false
            }
        }
    }

    private func scoreboardContent(containerWidth: CGFloat) -> some View {
        let base = containerWidth * Self.baseRatio
        // セットカウントバッジ用の上部余白（バッジが clipShape で見切れないように）
        let setCountTopExtra: CGFloat = style.showSetCount ? base * 0.55 : 0
        // メインセクション（スコア丸 + 上下パディング）で決まる高さ + バッジ用余白
        let containerH = base * 1.4 + base * 0.3125 * 2 + setCountTopExtra

        return HStack(spacing: 0) {
            // Period label (LEFT: before timer)
            if style.timerPosition == .left {
                periodLabelSection(base: base)
            }

            // Timer section (LEFT position)
            if style.timerPosition == .left {
                timerSection(base: base)
            }

            // Main section: team names + score circles
            HStack(spacing: base * 0.375) {
                // Home team name with underline
                teamLabel(
                    name: homeTeamName,
                    color: effectiveHomeColor,
                    base: base,
                    team: .home
                )

                // Home timeout dots (team name と score の間)
                timeoutColumn(team: .home, base: base)

                if style.showScore {
                    // Home score circle
                    scoreCircle(homeScore, base: base, flashing: homeFlash)
                        .overlay(alignment: .top) {
                            setCountBadge(homeSetCount, base: base)
                        }
                    // Away score circle
                    scoreCircle(awayScore, base: base, flashing: awayFlash)
                        .overlay(alignment: .top) {
                            setCountBadge(awaySetCount, base: base)
                        }
                } else {
                    Text("vs")
                        .font(.system(size: base * 0.6, weight: .semibold))
                        .foregroundStyle(Color.scoreboardText(for: style.theme).opacity(0.6))
                }

                // Away timeout dots (score と team name の間)
                timeoutColumn(team: .away, base: base)

                // Away team name with underline
                teamLabel(
                    name: awayTeamName,
                    color: effectiveAwayColor,
                    base: base,
                    team: .away
                )
            }
            .padding(.horizontal, base * 0.5)
            .padding(.vertical, base * 0.3125)

            // Timer section (RIGHT position)
            if style.timerPosition == .right {
                timerSection(base: base)
                periodLabelSection(base: base)
            }
        }
        .padding(.top, setCountTopExtra)
        .frame(height: containerH)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color.scoreboardBackground(for: style.theme))
        .clipShape(RoundedRectangle(cornerRadius: base * 0.375))
    }

    @ViewBuilder
    private func periodLabelSection(base: CGFloat) -> some View {
        if let label = currentPeriodLabel, !label.isEmpty {
            Text(label)
                .font(.system(size: base * 0.55, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, base * 0.375)
                .frame(maxHeight: .infinity)
                .background(.white)
        }
    }

    @ViewBuilder
    private func timerSection(base: CGFloat) -> some View {
        if style.showMatchTimer, currentPeriodLabel?.lowercased() != "pk" {
            let timerColor = timerDisplayColor ?? Color.scoreboardTimerText(for: style.theme)
            let sec = currentMatchSeconds()
            let mm = sec / 60
            let ss = sec % 60
            let timeStr = timerShowPlusPrefix
                ? String(format: "+%02d:%02d", mm, ss)
                : String(format: "%02d:%02d", mm, ss)
            Text(timeStr)
                .font(.custom("Arial-BoldMT", size: base * 0.6))
                .foregroundStyle(timerColor)
                .padding(.horizontal, base * 0.5)
                .frame(maxHeight: .infinity)
                .background(Color.scoreboardText(for: style.theme))
                .monospacedDigit()
        }
    }

    /// ScoreboardLayerBuilder.matchSecond(from:) と同じロジックでリアルタイムの試合経過秒数を計算
    private func currentMatchSeconds() -> Int {
        guard !timerSegments.isEmpty else { return 0 }
        let videoTime = currentVideoTime
        var lastMatchSecond = 0

        for seg in timerSegments {
            let effStart = seg.effectiveStartTime
            guard let kickoff = seg.timerStartTime ?? effStart else { continue }
            let segStart = effStart ?? kickoff
            let stop = seg.timerStopTime ?? videoTime
            let offset = Int(seg.timerStartOffset ?? 0)

            if videoTime >= segStart && videoTime <= stop {
                if videoTime < kickoff {
                    return offset
                }
                let elapsed = videoTime - kickoff
                let paused = timeouts.reduce(TimeInterval(0)) { sum, timeout in
                    sum + timeout.pausedSeconds(from: kickoff, to: videoTime)
                }
                return max(0, Int(elapsed - paused)) + offset
            } else if videoTime > stop {
                let elapsed = stop - kickoff
                let paused = timeouts.reduce(TimeInterval(0)) { sum, timeout in
                    sum + timeout.pausedSeconds(from: kickoff, to: stop)
                }
                lastMatchSecond = max(0, Int(elapsed - paused)) + offset
            } else {
                break
            }
        }
        return lastMatchSecond
    }

    private func matchInfoContent(info: String, containerWidth: CGFloat) -> some View {
        let base = containerWidth * Self.baseRatio
        return Text(info)
            .font(.system(size: base * 0.45, weight: .medium))
            .foregroundStyle(Color.scoreboardText(for: style.theme))
            .padding(.horizontal, base * 0.5)
            .padding(.vertical, base * 0.2)
            .background(Color.scoreboardBackground(for: style.theme))
            .clipShape(RoundedRectangle(cornerRadius: base * 0.375))
    }

    private func teamLabel(name: String, color: Color, base: CGFloat, team: Team) -> some View {
        VStack(spacing: base * 0.125) {
            Text(name)
                .font(.system(size: base * 0.65, weight: .semibold))
                .foregroundStyle(Color.scoreboardText(for: style.theme))
                .lineLimit(1)

            Rectangle()
                .fill(color)
                .frame(height: base * 0.125)
        }
        .padding(.horizontal, base * 0.65 * 2) // 2文字分の余白
    }

    /// タイムアウト回数の縦並び表示（最大3つ/列、常に上から配置）
    /// - ホーム側は内側(スコア寄り)から外側(チーム名寄り)に列を追加 → 列順を反転
    /// - アウェイ側は内側から外側 → 列順そのまま
    @ViewBuilder
    private func timeoutColumn(team: Team, base: CGFloat) -> some View {
        let visibleTimeouts: [TimeoutEvent] = style.showTimeouts
            ? timeouts
                .filter { $0.team == team && $0.timestamp <= currentVideoTime }
                .sorted { $0.timestamp < $1.timestamp }
            : []
        let count = visibleTimeouts.count
        if count > 0 {
            let maxRows = 3
            let cols = (count + maxRows - 1) / maxRows
            let dotSize = base * 0.3
            let spacing = base * 0.1
            let columnHeight = CGFloat(maxRows) * dotSize + CGFloat(maxRows - 1) * spacing
            // 論理列順: 0 が最初 (内側)。ホームは反転して右端を最初に描画
            let order: [Int] = team == .home
                ? Array((0..<cols).reversed())
                : Array(0..<cols)
            HStack(alignment: .top, spacing: spacing) {
                ForEach(order, id: \.self) { logicalCol in
                    let rowsInCol = min(maxRows, count - logicalCol * maxRows)
                    VStack(alignment: .center, spacing: spacing) {
                        ForEach(0..<maxRows, id: \.self) { row in
                            if row < rowsInCol {
                                let idx = logicalCol * maxRows + row
                                let isActive = visibleTimeouts[idx].isActive(at: currentVideoTime)
                                Circle()
                                    .fill(isActive ? Color.red : Color.yellow)
                                    .frame(width: dotSize, height: dotSize)
                            } else {
                                Color.clear
                                    .frame(width: dotSize, height: dotSize)
                            }
                        }
                    }
                    .frame(height: columnHeight, alignment: .top)
                }
            }
            .frame(height: columnHeight, alignment: .top)
        }
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let s = Int(ceil(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    @ViewBuilder
    private func setCountBadge(_ count: Int, base: CGFloat) -> some View {
        if style.showSetCount {
            Text("[\(count)]")
                .font(.system(size: base * 0.4, weight: .bold))
                .foregroundStyle(.yellow)
                .padding(.horizontal, base * 0.2)
                .padding(.vertical, base * 0.05)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.75))
                )
                .offset(y: -base * 0.55)
                .contentTransition(.numericText())
                .animation(.bouncy(duration: 0.4, extraBounce: 0.2), value: count)
        }
    }

    private func scoreCircle(_ score: Int, base: CGFloat, flashing: Bool = false) -> some View {
        let height = base * 1.4
        let digitCount = max(1, String(score).count)
        let width = digitCount <= 2 ? height : height + CGFloat(digitCount - 2) * base * 0.7
        let bgColor = flashing ? flashColor : Color.scoreboardText(for: style.theme)
        return Text("\(score)")
            .font(.system(size: base * 0.85, weight: .bold))
            .foregroundStyle(Color.scoreboardTimerText(for: style.theme))
            .contentTransition(.numericText())
            .frame(width: width, height: height)
            .background(
                Capsule()
                    .fill(bgColor)
                    .animation(.easeInOut(duration: 0.2), value: flashing)
            )
            .scaleEffect(flashing ? 1.2 : 1.0)
            .animation(.bouncy(duration: 0.4, extraBounce: 0.3), value: flashing)
            .animation(.bouncy(duration: 0.4, extraBounce: 0.2), value: score)
    }

    // MARK: - Penalty Timer Overlay (outside scoreboard)

    @ViewBuilder
    private func penaltyTimerOverlay(containerWidth: CGFloat) -> some View {
        let base = containerWidth * Self.baseRatio
        let homeActive = penaltyTimers
            .filter { $0.team == .home && $0.remainingSeconds(at: currentVideoTime, timeouts: timeouts) != nil }
            .sorted { $0.timestamp < $1.timestamp }
        let awayActive = penaltyTimers
            .filter { $0.team == .away && $0.remainingSeconds(at: currentVideoTime, timeouts: timeouts) != nil }
            .sorted { $0.timestamp < $1.timestamp }

        if !homeActive.isEmpty || !awayActive.isEmpty {
            HStack(spacing: base * 0.5) {
                // Home penalty timers
                if !homeActive.isEmpty {
                    HStack(spacing: base * 0.2) {
                        Text(homeTeamName)
                            .font(.system(size: base * 0.45, weight: .semibold))
                            .foregroundStyle(Color.scoreboardText(for: style.theme))
                            .lineLimit(1)
                        ForEach(homeActive) { timer in
                            if let remaining = timer.remainingSeconds(at: currentVideoTime, timeouts: timeouts) {
                                Text(formatCountdown(remaining))
                                    .font(.custom("Arial-BoldMT", size: base * 0.45))
                                    .foregroundStyle(.yellow)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                // Away penalty timers
                if !awayActive.isEmpty {
                    HStack(spacing: base * 0.2) {
                        Text(awayTeamName)
                            .font(.system(size: base * 0.45, weight: .semibold))
                            .foregroundStyle(Color.scoreboardText(for: style.theme))
                            .lineLimit(1)
                        ForEach(awayActive) { timer in
                            if let remaining = timer.remainingSeconds(at: currentVideoTime, timeouts: timeouts) {
                                Text(formatCountdown(remaining))
                                    .font(.custom("Arial-BoldMT", size: base * 0.45))
                                    .foregroundStyle(.yellow)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, base * 0.4)
            .padding(.vertical, base * 0.2)
            .background(Color.scoreboardBackground(for: style.theme))
            .clipShape(RoundedRectangle(cornerRadius: base * 0.375))
        }
    }

    // MARK: - PK Display

    private func pkContent(containerWidth: CGFloat) -> some View {
        let base = containerWidth * Self.baseRatio
        let homePK = pkKicks.filter { $0.team == .home }.sorted { $0.order < $1.order }
        let awayPK = pkKicks.filter { $0.team == .away }.sorted { $0.order < $1.order }

        let homeFirst = pkKicks.firstKickingTeam == .home

        return VStack(alignment: .leading, spacing: base * 0.2) {
            if homeFirst {
                pkRow(teamName: homeTeamName, kicks: homePK, base: base)
                pkRow(teamName: awayTeamName, kicks: awayPK, base: base)
            } else {
                pkRow(teamName: awayTeamName, kicks: awayPK, base: base)
                pkRow(teamName: homeTeamName, kicks: homePK, base: base)
            }
        }
        .padding(.horizontal, base * 0.4)
        .padding(.vertical, base * 0.25)
        .background(Color.scoreboardBackground(for: style.theme))
        .clipShape(RoundedRectangle(cornerRadius: base * 0.375))
    }

    private func pkRow(teamName: String, kicks: [PKKick], base: CGFloat) -> some View {
        HStack(spacing: base * 0.15) {
            Text(teamName)
                .font(.system(size: base * 0.5, weight: .semibold))
                .foregroundStyle(Color.scoreboardText(for: style.theme))
                .lineLimit(1)
                .frame(minWidth: base * 2.5, alignment: .leading)
            ForEach(kicks) { kick in
                Text(kick.isGoal ? "◯" : "✗")
                    .font(.system(size: base * 0.55, weight: .bold))
                    .foregroundStyle(kick.isGoal ? .green : .red)
                    .frame(width: base * 0.7)
            }
        }
    }
}

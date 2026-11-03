import SwiftUI

struct ScoreControlsView: View {
    let match: Match
    let currentTime: TimeInterval
    let onGoal: (Team) -> Void
    let onUndo: () -> Void
    let onSetWon: (Team) -> Void
    let onSetUndo: () -> Void
    let onPKKick: (Team, Bool) -> Void
    let onPKUndo: () -> Void
    let onSegmentStart: (Int) -> Void
    let onSegmentTimerStart: (Int) -> Void
    let onSegmentTimerStop: (Int) -> Void
    let onSegmentTimerClear: (Int) -> Void
    let onSegmentOffsetChange: (Int, TimeInterval) -> Void
    let onSegmentPeriodLabel: (Int, String?) -> Void
    let onSegmentShowPlusPrefix: (Int, Bool) -> Void
    let onSegmentTimerColor: (Int, String?) -> Void
    let onSegmentTeamColor: (Int, Team, String?) -> Void
    let onAddSegment: () -> Void
    let onAddSegmentWithRestart: () -> Void
    let onRemoveSegment: (Int) -> Void
    let onAddPenaltyTimer: (Team, TimeInterval) -> Void
    let onRemovePenaltyTimer: (UUID) -> Void
    let onStartTimeout: (Team) -> Void
    let onEndTimeout: (UUID, TimeInterval) -> Void
    let onRemoveTimeout: (UUID) -> Void

    /// タイマー・セグメント設定セクションの開閉。既にタイマー設定済みの試合では開いた状態で開始する。
    @State private var showSegmentSettings: Bool

    init(
        match: Match,
        currentTime: TimeInterval,
        onGoal: @escaping (Team) -> Void,
        onUndo: @escaping () -> Void,
        onSetWon: @escaping (Team) -> Void,
        onSetUndo: @escaping () -> Void,
        onPKKick: @escaping (Team, Bool) -> Void,
        onPKUndo: @escaping () -> Void,
        onSegmentStart: @escaping (Int) -> Void,
        onSegmentTimerStart: @escaping (Int) -> Void,
        onSegmentTimerStop: @escaping (Int) -> Void,
        onSegmentTimerClear: @escaping (Int) -> Void,
        onSegmentOffsetChange: @escaping (Int, TimeInterval) -> Void,
        onSegmentPeriodLabel: @escaping (Int, String?) -> Void,
        onSegmentShowPlusPrefix: @escaping (Int, Bool) -> Void,
        onSegmentTimerColor: @escaping (Int, String?) -> Void,
        onSegmentTeamColor: @escaping (Int, Team, String?) -> Void,
        onAddSegment: @escaping () -> Void,
        onAddSegmentWithRestart: @escaping () -> Void,
        onRemoveSegment: @escaping (Int) -> Void,
        onAddPenaltyTimer: @escaping (Team, TimeInterval) -> Void,
        onRemovePenaltyTimer: @escaping (UUID) -> Void,
        onStartTimeout: @escaping (Team) -> Void,
        onEndTimeout: @escaping (UUID, TimeInterval) -> Void,
        onRemoveTimeout: @escaping (UUID) -> Void
    ) {
        self.match = match
        self.currentTime = currentTime
        self.onGoal = onGoal
        self.onUndo = onUndo
        self.onSetWon = onSetWon
        self.onSetUndo = onSetUndo
        self.onPKKick = onPKKick
        self.onPKUndo = onPKUndo
        self.onSegmentStart = onSegmentStart
        self.onSegmentTimerStart = onSegmentTimerStart
        self.onSegmentTimerStop = onSegmentTimerStop
        self.onSegmentTimerClear = onSegmentTimerClear
        self.onSegmentOffsetChange = onSegmentOffsetChange
        self.onSegmentPeriodLabel = onSegmentPeriodLabel
        self.onSegmentShowPlusPrefix = onSegmentShowPlusPrefix
        self.onSegmentTimerColor = onSegmentTimerColor
        self.onSegmentTeamColor = onSegmentTeamColor
        self.onAddSegment = onAddSegment
        self.onAddSegmentWithRestart = onAddSegmentWithRestart
        self.onRemoveSegment = onRemoveSegment
        self.onAddPenaltyTimer = onAddPenaltyTimer
        self.onRemovePenaltyTimer = onRemovePenaltyTimer
        self.onStartTimeout = onStartTimeout
        self.onEndTimeout = onEndTimeout
        self.onRemoveTimeout = onRemoveTimeout
        // 既にキックオフ/区切りが記録済みなら設定を開いて表示
        let hasTimerConfig = match.timerSegments.contains {
            $0.timerStartTime != nil || $0.segmentStartTime != nil
        }
        _showSegmentSettings = State(initialValue: hasTimerConfig)
    }

    static let periodPresets: [String] = [
        String(localized: "前半"),
        String(localized: "後半"),
        String(localized: "延前"),
        String(localized: "延後"),
        "PK"
    ]

    private var periodPresets: [String] {
        match.sportType.periodPresets
    }

    /// ゴールボタンの色。チームカラー（セクション別設定を含む）があればそれを使い、未設定なら従来色。
    private func goalButtonColor(for team: Team) -> Color {
        match.editorTeamColor(at: currentTime, for: team)
    }

    private var isPKMode: Bool {
        match.currentPeriodLabel(at: currentTime)?.lowercased() == "pk"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(match.homeTeamName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                VStack(spacing: 2) {
                    if match.scoreboardStyle.showSetCount {
                        Text("[\(match.homeSetCount)] - [\(match.awaySetCount)]")
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)
                            .monospacedDigit()
                    }
                    Text("\(match.homeScore) - \(match.awayScore)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
                Spacer()
                Text(match.awayTeamName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal)

            HStack(spacing: 4) {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.caption2)
                Text("記録位置")
                    .font(.caption2)
                Text(TimeFormatting.format(seconds: currentTime))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.quaternary))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("記録位置 \(TimeFormatting.format(seconds: currentTime))")

            if isPKMode {
                PKStateView(match: match, currentTime: currentTime)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    PKTeamButtons(teamName: match.homeTeamName, color: .blue) { isGoal in
                        onPKKick(.home, isGoal)
                    }

                    Button {
                        onPKUndo()
                    } label: {
                        Label("取消", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(match.pkKicks.isEmpty)

                    PKTeamButtons(teamName: match.awayTeamName, color: .red) { isGoal in
                        onPKKick(.away, isGoal)
                    }
                }
                .padding(.horizontal)
            } else {
                HStack(spacing: 12) {
                    GoalButton(teamName: match.homeTeamName, color: goalButtonColor(for: .home), sportType: match.sportType) {
                        onGoal(.home)
                    }

                    Button {
                        onUndo()
                    } label: {
                        Label("取消", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!match.scoreEvents.contains { $0.kind == .point })

                    GoalButton(teamName: match.awayTeamName, color: goalButtonColor(for: .away), sportType: match.sportType) {
                        onGoal(.away)
                    }
                }
                .padding(.horizontal)

                // セット獲得ボタン (showSetCount時のみ表示)
                if match.scoreboardStyle.showSetCount {
                    HStack(spacing: 12) {
                        Button {
                            onSetWon(.home)
                        } label: {
                            Label("セット獲得", systemImage: "flag.checkered")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)

                        Button {
                            onSetUndo()
                        } label: {
                            Label("取消", systemImage: "arrow.uturn.backward")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!match.scoreEvents.contains { $0.kind == .setWon })

                        Button {
                            onSetWon(.away)
                        } label: {
                            Label("セット獲得", systemImage: "flag.checkered")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                    }
                    .padding(.horizontal)
                }
            }

            // Penalty timers
            if match.scoreboardStyle.showPenaltyTimer {
                PenaltyTimerSection(
                    match: match,
                    currentTime: currentTime,
                    onAdd: onAddPenaltyTimer,
                    onRemove: onRemovePenaltyTimer
                )
            }

            // Timeouts
            if match.scoreboardStyle.showTimeouts {
                TimeoutSection(
                    match: match,
                    currentTime: currentTime,
                    onStart: onStartTimeout,
                    onEnd: onEndTimeout,
                    onRemove: onRemoveTimeout
                )
            }

            // タイマー・セグメント設定（折りたたみ: 記録操作と分離して密度を下げる）
            DisclosureGroup(isExpanded: $showSegmentSettings) {
                segmentSettingsSection
                    .padding(.top, 4)
            } label: {
                Label(segmentSettingsLabel, systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    private var segmentSettingsLabel: String {
        let count = match.timerSegments.count
        return count > 1
            ? String(localized: "タイマー・セグメント設定 (\(count))")
            : String(localized: "タイマー・セグメント設定")
    }

    @ViewBuilder
    private var segmentSettingsSection: some View {
        VStack(spacing: 8) {
            // セグメント追加ボタン
            HStack(spacing: 8) {
                Button {
                    onAddSegment()
                } label: {
                    Label("セグメント追加", systemImage: "plus.circle")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                if match.timerSegments.contains(where: { $0.timerStartTime != nil }) {
                    Button {
                        onAddSegmentWithRestart()
                    } label: {
                        Label("タイマー引き継ぎ", systemImage: "arrow.clockwise.circle")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
            .padding(.horizontal)

            // Segment list (newest first)
            ForEach(Array(match.timerSegments.enumerated()).reversed(), id: \.offset) { index, segment in
                SegmentControlRow(
                    index: index,
                    segment: segment,
                    homeTeamName: match.homeTeamName,
                    awayTeamName: match.awayTeamName,
                    onSegmentStart: { onSegmentStart(index) },
                    onTimerStart: { onSegmentTimerStart(index) },
                    onTimerStop: { onSegmentTimerStop(index) },
                    onTimerClear: { onSegmentTimerClear(index) },
                    onOffsetChange: { onSegmentOffsetChange(index, $0) },
                    onPeriodLabel: { onSegmentPeriodLabel(index, $0) },
                    onShowPlusPrefix: { onSegmentShowPlusPrefix(index, $0) },
                    onTimerColor: { onSegmentTimerColor(index, $0) },
                    onTeamColor: { team, hex in onSegmentTeamColor(index, team, hex) },
                    onRemove: match.timerSegments.count > 1 ? { onRemoveSegment(index) } : nil,
                    showTimerOptions: match.scoreboardStyle.showTimerOptions,
                    showTeamColors: match.scoreboardStyle.useSegmentTeamColors,
                    periodPresets: periodPresets
                )
            }
        }
    }
}

// MARK: - Segment Control Row

private struct SegmentControlRow: View {
    let index: Int
    let segment: TimerSegment
    var homeTeamName: String = ""
    var awayTeamName: String = ""
    let onSegmentStart: () -> Void
    let onTimerStart: () -> Void
    let onTimerStop: () -> Void
    let onTimerClear: () -> Void
    let onOffsetChange: (TimeInterval) -> Void
    let onPeriodLabel: (String?) -> Void
    let onShowPlusPrefix: (Bool) -> Void
    let onTimerColor: (String?) -> Void
    var onTeamColor: ((Team, String?) -> Void)? = nil
    let onRemove: (() -> Void)?
    var showTimerOptions: Bool = false
    var showTeamColors: Bool = false
    var periodPresets: [String] = ScoreControlsView.periodPresets

    /// セグメント削除の確認ダイアログ表示（誤タップによる設定喪失を防ぐ）
    @State private var showRemoveConfirm = false

    static func hexString(from uiColor: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private var currentTimerColor: Color {
        guard let hex = segment.timerColorHex else { return .white }
        return Color(uiColor: UIColor(hex: hex) ?? .white)
    }

    private var totalOffsetSeconds: Int { Int(segment.timerStartOffset ?? 0) }
    private var offsetMinutes: Int { totalOffsetSeconds / 60 }
    private var offsetSeconds: Int { totalOffsetSeconds % 60 }

    var body: some View {
        VStack(spacing: 6) {
            // ヘッダー
            HStack {
                Text("セグメント \(index + 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if onRemove != nil {
                    Button(role: .destructive) {
                        showRemoveConfirm = true
                    } label: {
                        Image(systemName: "trash.circle")
                            .font(.caption)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .confirmationDialog(
                        "セグメント \(index + 1) を削除しますか？",
                        isPresented: $showRemoveConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("削除", role: .destructive) {
                            onRemove?()
                        }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        Text("キックオフ時刻やラベルなどの設定が失われます。")
                    }
                }
            }

            // ピリオドラベル
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(periodPresets, id: \.self) { preset in
                        Button(preset) {
                            onPeriodLabel(segment.periodLabel == preset ? nil : preset)
                        }
                        .buttonStyle(.bordered)
                        .tint(segment.periodLabel == preset ? .accentColor : .secondary)
                        .controlSize(.small)
                    }

                    TextField("ラベル", text: Binding(
                        get: {
                            let current = segment.periodLabel ?? ""
                            return periodPresets.contains(current) ? "" : current
                        },
                        set: { newValue in
                            onPeriodLabel(newValue.isEmpty ? nil : newValue)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 80)
                }
            }

            // タイマー操作行
            HStack(spacing: 8) {
                Button {
                    onSegmentStart()
                } label: {
                    VStack(spacing: 2) {
                        Label("区切り開始", systemImage: "flag.circle")
                            .font(.caption2.weight(.semibold))
                        if let segStart = segment.segmentStartTime {
                            Text(TimeFormatting.format(seconds: segStart))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.purple)

                Button {
                    onTimerStart()
                } label: {
                    VStack(spacing: 2) {
                        Label("キックオフ", systemImage: "play.circle")
                            .font(.caption2.weight(.semibold))
                        if let start = segment.timerStartTime {
                            Text(TimeFormatting.format(seconds: start))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button {
                    onTimerStop()
                } label: {
                    VStack(spacing: 2) {
                        Label("試合終了", systemImage: "stop.circle")
                            .font(.caption2.weight(.semibold))
                        if let stop = segment.timerStopTime {
                            Text(TimeFormatting.format(seconds: stop))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(segment.timerStartTime == nil && segment.segmentStartTime == nil)

                if segment.segmentStartTime != nil || segment.timerStartTime != nil || segment.timerStopTime != nil {
                    Button {
                        onTimerClear()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
            }

            // 開始時間オフセット調整行 (MM:SS)
            if segment.timerStartTime != nil {
                HStack(spacing: 4) {
                    Text("開始時間")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // 分の調整
                    Button {
                        onOffsetChange(TimeInterval((offsetMinutes - 1) * 60 + offsetSeconds))
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.caption)
                    }
                    .disabled(offsetMinutes <= 0)

                    Text(String(format: "%02d", offsetMinutes))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .frame(minWidth: 22)

                    Button {
                        onOffsetChange(TimeInterval((offsetMinutes + 1) * 60 + offsetSeconds))
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                    }

                    Text(":")
                        .font(.caption.weight(.medium))

                    // 秒の調整
                    Button {
                        onOffsetChange(TimeInterval(offsetMinutes * 60 + offsetSeconds - 1))
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.caption)
                    }
                    .disabled(totalOffsetSeconds <= 0)

                    Text(String(format: "%02d", offsetSeconds))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .frame(minWidth: 22)

                    Button {
                        let newSeconds = offsetSeconds + 1
                        if newSeconds >= 60 {
                            onOffsetChange(TimeInterval((offsetMinutes + 1) * 60))
                        } else {
                            onOffsetChange(TimeInterval(offsetMinutes * 60 + newSeconds))
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                    }
                }

                // タイマー表示オプション（+表示 / 色）
                if showTimerOptions {
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { segment.showPlusPrefix },
                        set: { onShowPlusPrefix($0) }
                    )) {
                        Text("+表示")
                            .font(.caption2)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .tint(.orange)

                    Spacer()

                    Text("タイマー色")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { currentTimerColor },
                            set: { newColor in
                                let uiColor = UIColor(newColor)
                                onTimerColor(SegmentControlRow.hexString(from: uiColor))
                            }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 28, height: 28)

                    if segment.timerColorHex != nil {
                        Button {
                            onTimerColor(nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                } // showTimerOptions
            }

            // セクション別チームカラー設定
            if showTeamColors, let onTeamColor {
                segmentTeamColorRow(onTeamColor: onTeamColor)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
        .padding(.horizontal)
    }

    private func teamColor(forHex hex: String?, fallback: Color) -> Color {
        guard let hex, let ui = UIColor(hex: hex) else { return fallback }
        return Color(uiColor: ui)
    }

    @ViewBuilder
    private func segmentTeamColorRow(onTeamColor: @escaping (Team, String?) -> Void) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("チームカラー")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if segment.homeTeamColorHex != nil || segment.awayTeamColorHex != nil {
                    Button {
                        onTeamColor(.home, nil)
                        onTeamColor(.away, nil)
                    } label: {
                        Text("リセット")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            HStack(spacing: 12) {
                segmentTeamColorPicker(
                    team: .home,
                    teamName: homeTeamName,
                    hex: segment.homeTeamColorHex,
                    onChange: { onTeamColor(.home, $0) }
                )
                segmentTeamColorPicker(
                    team: .away,
                    teamName: awayTeamName,
                    hex: segment.awayTeamColorHex,
                    onChange: { onTeamColor(.away, $0) }
                )
            }
        }
    }

    @ViewBuilder
    private func segmentTeamColorPicker(
        team: Team,
        teamName: String,
        hex: String?,
        onChange: @escaping (String?) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(teamName.isEmpty ? (team == .home ? "ホーム" : "アウェイ") : teamName)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ColorPicker(
                "",
                selection: Binding(
                    get: { teamColor(forHex: hex, fallback: .gray) },
                    set: { newColor in
                        let uiColor = UIColor(newColor)
                        onChange(SegmentControlRow.hexString(from: uiColor))
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 28, height: 28)

            if hex != nil {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.tertiary, lineWidth: 1)
        )
    }
}

// MARK: - PK State Display

private struct PKStateView: View {
    let match: Match
    let currentTime: TimeInterval

    var body: some View {
        let visibleKicks = match.pkKicksAt(time: currentTime)
        let homeKicks = visibleKicks.filter { $0.team == .home }.sorted { $0.order < $1.order }
        let awayKicks = visibleKicks.filter { $0.team == .away }.sorted { $0.order < $1.order }
        let homeGoals = homeKicks.filter(\.isGoal).count
        let awayGoals = awayKicks.filter(\.isGoal).count

        VStack(spacing: 4) {
            Text("PK \(homeGoals) - \(awayGoals)")
                .font(.caption.weight(.bold))
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 2) {
                PKMarkRow(teamName: match.homeTeamName, kicks: homeKicks)
                PKMarkRow(teamName: match.awayTeamName, kicks: awayKicks)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }
}

private struct PKMarkRow: View {
    let teamName: String
    let kicks: [PKKick]

    var body: some View {
        HStack(spacing: 4) {
            Text(teamName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)
            ForEach(kicks) { kick in
                Text(kick.isGoal ? "◯" : "✗")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(kick.isGoal ? .green : .red)
                    .frame(width: 18)
            }
        }
    }
}

// MARK: - PK Team Buttons

private struct PKTeamButtons: View {
    let teamName: String
    let color: Color
    let onKick: (Bool) -> Void
    @State private var tapCount = 0

    var body: some View {
        VStack(spacing: 4) {
            Text(teamName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Button {
                    tapCount += 1
                    onKick(true)
                } label: {
                    Text("◯")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    tapCount += 1
                    onKick(false)
                } label: {
                    Text("✗")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: tapCount)
    }
}

// MARK: - Goal Button

private struct GoalButton: View {
    let teamName: String
    let color: Color
    var sportType: SportType = .soccer
    let action: () -> Void
    @State private var tapCount = 0

    var body: some View {
        Button {
            tapCount += 1
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: sportType.goalSystemImage)
                    .font(.title3)
                Text(sportType.goalButtonLabel)
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .foregroundStyle(color.prefersDarkForeground ? Color.black : Color.white)
        .sensoryFeedback(.impact(weight: .heavy), trigger: tapCount)
    }
}

// MARK: - Penalty Timer Section

// MARK: - Timeout Section

private struct TimeoutSection: View {
    let match: Match
    let currentTime: TimeInterval
    let onStart: (Team) -> Void
    let onEnd: (UUID, TimeInterval) -> Void
    let onRemove: (UUID) -> Void

    private var activeTimeout: TimeoutEvent? {
        match.timeouts.first { $0.isActive(at: currentTime) }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("タイムアウト")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                let homeCount = match.timeoutCount(for: .home, at: currentTime)
                let awayCount = match.timeoutCount(for: .away, at: currentTime)
                Text("\(match.homeTeamName): \(homeCount)  \(match.awayTeamName): \(awayCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // アクティブなタイムアウト表示
            if let active = activeTimeout {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .font(.title3)
                        .foregroundStyle(active.team == .home ? .blue : .red)
                    Text(active.team == .home ? match.homeTeamName : match.awayTeamName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if let elapsed = active.elapsedSeconds(at: currentTime) {
                        Text(TimeFormatting.format(seconds: elapsed))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                }

                // タイムアウト終了ボタン
                Button {
                    onEnd(active.id, currentTime)
                } label: {
                    Label("タイムアウト終了", systemImage: "play.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                // 削除ボタン
                Button {
                    onRemove(active.id)
                } label: {
                    Label("取消", systemImage: "xmark.circle")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            } else {
                // タイムアウト開始ボタン
                HStack(spacing: 12) {
                    Button {
                        onStart(.home)
                    } label: {
                        Label(match.homeTeamName, systemImage: "pause.circle")
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button {
                        onStart(.away)
                    } label: {
                        Label(match.awayTeamName, systemImage: "pause.circle")
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
        .padding(.horizontal)
    }
}

private struct PenaltyTimerSection: View {
    let match: Match
    let currentTime: TimeInterval
    let onAdd: (Team, TimeInterval) -> Void
    let onRemove: (UUID) -> Void
    @State private var showingCustomSheet: Team? = nil
    /// 削除確認中のペナルティタイマーID（誤タップによる即削除を防ぐ）
    @State private var confirmingRemoveID: UUID?

    static let presets: [(label: String, seconds: TimeInterval)] = [
        ("2分", 120),
        ("5分", 300),
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("ペナルティタイマー")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // アクティブなタイマー表示
            let homeActive = match.activePenaltyTimers(at: currentTime, for: .home)
            let awayActive = match.activePenaltyTimers(at: currentTime, for: .away)

            if !homeActive.isEmpty || !awayActive.isEmpty {
                VStack(spacing: 4) {
                    ForEach(homeActive) { timer in
                        penaltyRow(timer: timer, teamName: match.homeTeamName, color: .blue)
                    }
                    ForEach(awayActive) { timer in
                        penaltyRow(timer: timer, teamName: match.awayTeamName, color: .red)
                    }
                }
            }

            // 追加ボタン
            HStack(spacing: 8) {
                penaltyAddButtons(teamName: match.homeTeamName, team: .home, color: .blue)
                Spacer()
                penaltyAddButtons(teamName: match.awayTeamName, team: .away, color: .red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
        .padding(.horizontal)
        .sheet(item: $showingCustomSheet) { team in
            PenaltyDurationSheet(
                team: team,
                teamName: team == .home ? match.homeTeamName : match.awayTeamName,
                onAdd: onAdd
            )
            .presentationDetents([.height(280)])
        }
        .confirmationDialog(
            "このペナルティタイマーを削除しますか？",
            isPresented: Binding(
                get: { confirmingRemoveID != nil },
                set: { if !$0 { confirmingRemoveID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let id = confirmingRemoveID {
                    onRemove(id)
                }
                confirmingRemoveID = nil
            }
            Button("キャンセル", role: .cancel) {
                confirmingRemoveID = nil
            }
        }
    }

    private func penaltyRow(timer: PenaltyTimer, teamName: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.caption)
                .foregroundStyle(color)
            Text(teamName)
                .font(.caption2)
                .lineLimit(1)
            Spacer()
            if let remaining = timer.remainingSeconds(at: currentTime, timeouts: match.timeouts) {
                Text(TimeFormatting.format(seconds: remaining))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.yellow)
            }
            Button {
                confirmingRemoveID = timer.id
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func penaltyAddButtons(teamName: String, team: Team, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(teamName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                ForEach(Self.presets, id: \.seconds) { preset in
                    Button {
                        onAdd(team, preset.seconds)
                    } label: {
                        Text(preset.label)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(color)
                    .controlSize(.mini)
                }
                Button {
                    showingCustomSheet = team
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(color)
                .controlSize(.mini)
            }
        }
    }
}

// MARK: - Custom Penalty Duration Sheet

private struct PenaltyDurationSheet: View {
    let team: Team
    let teamName: String
    let onAdd: (Team, TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int = 2
    @State private var seconds: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(String(format: "%d:%02d", minutes, seconds))
                    .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                    .monospacedDigit()
                    .padding(.top, 8)

                HStack(spacing: 40) {
                    VStack(spacing: 6) {
                        Button { minutes += 1 } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                        Text("\(minutes)")
                            .font(.title3.weight(.medium))
                            .monospacedDigit()
                            .frame(minWidth: 40)
                        Button { minutes = max(0, minutes - 1) } label: {
                            Image(systemName: "minus.circle.fill").font(.title2)
                        }
                        .disabled(minutes <= 0 && seconds <= 0)
                        Text("分").font(.caption).foregroundStyle(.secondary)
                    }

                    Text(":").font(.title).foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        Button {
                            seconds += 10
                            if seconds >= 60 { minutes += 1; seconds -= 60 }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                        Text(String(format: "%02d", seconds))
                            .font(.title3.weight(.medium))
                            .monospacedDigit()
                            .frame(minWidth: 40)
                        Button {
                            seconds -= 10
                            if seconds < 0 { minutes = max(0, minutes - 1); seconds += 60 }
                            if minutes <= 0 && seconds < 0 { seconds = 0 }
                        } label: {
                            Image(systemName: "minus.circle.fill").font(.title2)
                        }
                        .disabled(minutes <= 0 && seconds <= 0)
                        Text("秒").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .navigationTitle("ペナルティ時間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        let total = TimeInterval(minutes * 60 + seconds)
                        if total > 0 { onAdd(team, total) }
                        dismiss()
                    }
                    .disabled(minutes == 0 && seconds == 0)
                }
            }
        }
    }
}

// MARK: - UIColor hex helper

private extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red:   CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8)  & 0xFF) / 255,
            blue:  CGFloat(value         & 0xFF) / 255,
            alpha: 1
        )
    }
}

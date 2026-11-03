import SwiftUI
import SwiftData

struct ScoreEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(Router.self) private var router
    @Bindable var match: Match
    @State private var playerVM: PlayerViewModel?
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0

    /// 動画プレイヤーの読み込み状態。playerVM が非nilなら読み込み完了。
    private enum PlayerLoadState {
        case loading   // 動画あり・読み込み中
        case noVideo   // 動画未追加（ライブ記録モード）
        case failed    // 動画はあるが読み込みに失敗
    }
    @State private var loadState: PlayerLoadState = .loading

    // ライブストップウォッチ（動画なし時）
    @State private var liveElapsed: TimeInterval = 0
    @State private var liveIsRunning = false
    @State private var liveStartDate: Date? = nil
    @State private var liveDisplayTime: TimeInterval = 0
    /// ライブタイマーのリセット確認（計測中の経過時間を誤って失わないため）
    @State private var showResetConfirm = false

    private var currentTime: TimeInterval {
        playerVM?.currentTime ?? 0
    }

    private var liveCurrentTime: TimeInterval { liveDisplayTime }

    var body: some View {
        Group {
            if let playerVM {
                if horizontalSizeClass == .regular {
                    iPadLayout(playerVM: playerVM)
                } else {
                    iPhoneLayout(playerVM: playerVM)
                }
            } else {
                switch loadState {
                case .loading:
                    ProgressView("動画を準備中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .noVideo:
                    noVideoLayout()
                case .failed:
                    videoLoadErrorView()
                }
            }
        }
        .navigationTitle("スコア記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    playerVM?.pause()
                    pauseLiveTimer()
                    router.popToRoot()
                    router.navigate(to: .matchDetail(match))
                }
            }
        }
        .onAppear {
            setupPlayer()
            ensureAtLeastOneSegment()
        }
        .onDisappear {
            playerVM?.pause()
            pauseLiveTimer()
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            if liveIsRunning, let start = liveStartDate {
                liveDisplayTime = liveElapsed + Date().timeIntervalSince(start)
            }
        }
    }

    // MARK: - iPhone Layout (縦積み・画面全体利用)

    private func iPhoneLayout(playerVM: PlayerViewModel) -> some View {
        VStack(spacing: 0) {
            videoWithOverlay(playerVM: playerVM)
                .aspectRatio(videoAspectRatio, contentMode: .fit)
                .clipped()

            PlaybackControlsView(playerVM: playerVM)
                .padding(.vertical, 6)

            goalTimeline(duration: playerVM.duration)
                .padding(.horizontal)

            ScrollView {
                scoreControls(currentTime: currentTime)
                    .padding(.vertical, 6)

                Divider()

                eventList()
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    // MARK: - iPad Layout (横並び)

    private func iPadLayout(playerVM: PlayerViewModel) -> some View {
        GeometryReader { geo in
            let rightWidth: CGFloat = 320
            let leftWidth = geo.size.width - rightWidth

            HStack(spacing: 0) {
                // 左: 動画 + 再生コントロール
                VStack(spacing: 0) {
                    videoWithOverlay(playerVM: playerVM)
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .frame(maxWidth: leftWidth)
                        .clipped()

                    PlaybackControlsView(playerVM: playerVM)
                        .padding(.vertical, 8)
                        .padding(.horizontal)

                    goalTimeline(duration: playerVM.duration)
                        .padding(.horizontal)

                    Spacer(minLength: 0)
                }
                .frame(width: leftWidth)

                Divider()

                // 右: スコアコントロール + イベントリスト
                ScrollView {
                    VStack(spacing: 0) {
                        scoreControls(currentTime: currentTime)
                            .padding(.vertical, 12)

                        Divider()

                        eventList()
                    }
                }
                .frame(width: rightWidth)
            }
        }
    }

    // MARK: - 動画なしレイアウト

    private func noVideoLayout() -> some View {
        ScrollView {
            liveStopwatchView()
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            scoreControls(currentTime: liveCurrentTime)
                .padding(.vertical, 6)

            Divider()

            eventList()
        }
    }

    /// 観ながらタップで記録したゴールを動画全体に対する位置の点で可視化する
    @ViewBuilder
    private func goalTimeline(duration: TimeInterval) -> some View {
        let goals = match.scoreEvents.filter { $0.kind == .point }
        Group {
            if duration > 0 && !goals.isEmpty {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(height: 6)
                            .frame(maxHeight: .infinity, alignment: .center)

                        ForEach(goals, id: \.id) { goal in
                            let ratio = min(max(goal.timestamp / duration, 0), 1)
                            let color = match.editorTeamColor(at: goal.timestamp, for: goal.team)
                            Circle()
                                .fill(color)
                                .overlay {
                                    // 白など明るいチームカラーでもトラック上で見えるよう縁取り
                                    if color.prefersDarkForeground {
                                        Circle().strokeBorder(.secondary, lineWidth: 1)
                                    }
                                }
                                .frame(width: 12, height: 12)
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                                .position(x: geo.size.width * ratio, y: geo.size.height / 2)
                                .onTapGesture {
                                    playerVM?.seek(to: goal.timestamp)
                                }
                                .accessibilityLabel("ゴール \(TimeFormatting.format(seconds: goal.timestamp)) へ移動")
                        }
                    }
                }
                .frame(height: 28)
            }
        }
    }

    private func eventList() -> some View {
        EventListView(
            events: match.scoreEvents,
            sportType: match.sportType,
            pkKicks: match.pkKicks,
            penaltyTimers: match.penaltyTimers,
            homeTeamName: match.homeTeamName,
            awayTeamName: match.awayTeamName,
            onDeleteGoal: { id in deleteGoal(id: id) },
            onEditGoalTimestamp: { id, time in updateGoalTimestamp(id: id, time: time) },
            onDeletePKKick: { id in deletePKKick(id: id) },
            onEditPKKickTimestamp: { id, time in updatePKKickTimestamp(id: id, time: time) },
            onDeletePenaltyTimer: { id in deletePenaltyTimer(id: id) },
            onEditPenaltyTimerTimestamp: { id, time in updatePenaltyTimerTimestamp(id: id, time: time) },
            timeouts: match.timeouts,
            onDeleteTimeout: { id in deleteTimeout(id: id) },
            onEditTimeoutTimestamp: { id, time in updateTimeoutTimestamp(id: id, time: time) },
            onSeek: playerVM != nil ? { time in playerVM?.seek(to: time) } : nil
        )
    }

    private func liveStopwatchView() -> some View {
        VStack(spacing: 8) {
            Text(TimeFormatting.format(seconds: liveCurrentTime))
                .font(.system(.title, design: .monospaced, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(liveIsRunning ? .primary : .secondary)

            HStack(spacing: 12) {
                Button {
                    if liveIsRunning {
                        pauseLiveTimer()
                    } else {
                        startLiveTimer()
                    }
                } label: {
                    Label(
                        liveIsRunning
                            ? String(localized: "一時停止")
                            : (liveElapsed > 0 ? String(localized: "再開") : String(localized: "開始")),
                        systemImage: liveIsRunning ? "pause.circle.fill" : "play.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(liveIsRunning ? .orange : .green)

                Button {
                    showResetConfirm = true
                } label: {
                    Label("リセット", systemImage: "arrow.counterclockwise.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .disabled(liveDisplayTime == 0)
                .confirmationDialog(
                    "タイマーをリセットしますか？",
                    isPresented: $showResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("リセット", role: .destructive) {
                        resetLiveTimer()
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("経過時間（\(TimeFormatting.format(seconds: liveDisplayTime))）が0に戻ります。")
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
    }

    private func videoWithOverlay(playerVM: PlayerViewModel) -> some View {
        ZoomableView {
            videoFrame(playerVM: playerVM)
        }
    }

    /// 動画 + スコアボードプレビュー。ズーム時は合成結果ごと拡大される。
    private func videoFrame(playerVM: PlayerViewModel) -> some View {
        ZStack {
            VideoPlayerView(player: playerVM.player)
                .background(.black)

            let currentTime = playerVM.currentTime
            let score = match.scoreAt(time: currentTime)
            let timerSeg = match.activeTimerSegment(at: currentTime)
            ScoreboardPreviewView(
                homeTeamName: match.homeTeamName,
                awayTeamName: match.awayTeamName,
                homeScore: score.home,
                awayScore: score.away,
                style: match.scoreboardStyle,
                currentPeriodLabel: match.currentPeriodLabel(at: currentTime),
                matchInfo: match.matchInfo,
                pkKicks: match.pkKicksAt(time: currentTime),
                videoAspectRatio: videoAspectRatio,
                timerShowPlusPrefix: timerSeg?.showPlusPrefix ?? false,
                timerDisplayColor: timerSeg?.timerColorHex.flatMap { Color(hex: $0) },
                penaltyTimers: match.penaltyTimers,
                timeouts: match.timeouts,
                timerSegments: match.timerSegments,
                currentVideoTime: currentTime,
                homeSetCount: match.effectiveSetCount(at: currentTime, for: .home),
                awaySetCount: match.effectiveSetCount(at: currentTime, for: .away)
            )
            .allowsHitTesting(false)
        }
    }

    private func scoreControls(currentTime: TimeInterval) -> some View {
        ScoreControlsView(
            match: match,
            currentTime: currentTime,
            onGoal: { team in addGoal(team: team, at: currentTime) },
            onUndo: { undoLastGoal() },
            onSetWon: { team in addSetWon(team: team, at: currentTime) },
            onSetUndo: { undoLastSetWon() },
            onPKKick: { team, isGoal in addPKKick(team: team, isGoal: isGoal, at: currentTime) },
            onPKUndo: { undoLastPKKick() },
            onSegmentStart: { idx in setSegmentStart(at: idx, time: currentTime) },
            onSegmentTimerStart: { idx in setSegmentTimerStart(at: idx, time: currentTime) },
            onSegmentTimerStop: { idx in setSegmentTimerStop(at: idx, time: currentTime) },
            onSegmentTimerClear: { idx in clearSegmentTimer(at: idx) },
            onSegmentOffsetChange: { idx, secs in setSegmentOffset(at: idx, seconds: secs) },
            onSegmentPeriodLabel: { idx, label in setSegmentPeriodLabel(at: idx, label: label) },
            onSegmentShowPlusPrefix: { idx, value in setSegmentShowPlusPrefix(at: idx, value: value) },
            onSegmentTimerColor: { idx, hex in setSegmentTimerColor(at: idx, hex: hex) },
            onSegmentTeamColor: { idx, team, hex in setSegmentTeamColor(at: idx, team: team, hex: hex) },
            onAddSegment: { addTimerSegment() },
            onAddSegmentWithRestart: { addTimerSegmentWithRestart(at: currentTime) },
            onRemoveSegment: { idx in removeTimerSegment(at: idx) },
            onAddPenaltyTimer: { team, duration in addPenaltyTimer(team: team, duration: duration, at: currentTime) },
            onRemovePenaltyTimer: { id in deletePenaltyTimer(id: id) },
            onStartTimeout: { team in startTimeout(team: team, at: currentTime) },
            onEndTimeout: { id, time in endTimeout(id: id, at: time) },
            onRemoveTimeout: { id in deleteTimeout(id: id) }
        )
    }

    // MARK: - Actions

    private func setupPlayer() {
        let urls = match.videoURLs
        guard !urls.isEmpty else {
            // 動画未追加: ライブ記録モードとして扱う
            loadState = .noVideo
            return
        }
        loadState = .loading
        Task {
            if let url = urls.first, let size = await ThumbnailGenerator.videoSize(for: url) {
                videoAspectRatio = size.width / size.height
            }
            do {
                playerVM = try await PlayerViewModel.create(urls: urls)
            } catch {
                // 動画はあるが読み込みに失敗 → エラー表示（再試行可能）
                loadState = .failed
            }
        }
    }

    private func videoLoadErrorView() -> some View {
        ContentUnavailableView {
            Label("動画を読み込めませんでした", systemImage: "exclamationmark.triangle")
        } description: {
            Text("動画ファイルが見つからないか、破損している可能性があります。動画管理から追加し直してください。")
        } actions: {
            Button {
                setupPlayer()
            } label: {
                Text("再試行")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func ensureAtLeastOneSegment() {
        if match.timerSegments.isEmpty {
            match.timerSegments = [TimerSegment()]
        }
    }

    private func addGoal(team: Team, at timestamp: TimeInterval) {
        let event = ScoreEvent(team: team, timestamp: timestamp, kind: .point)
        event.match = match
        match.scoreEvents.append(event)
        modelContext.insert(event)
    }

    private func undoLastGoal() {
        guard let lastEvent = match.scoreEvents
            .filter({ $0.kind == .point })
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last else {
            return
        }
        match.scoreEvents.removeAll { $0.id == lastEvent.id }
        modelContext.delete(lastEvent)
    }

    private func addSetWon(team: Team, at timestamp: TimeInterval) {
        let event = ScoreEvent(team: team, timestamp: timestamp, kind: .setWon)
        event.match = match
        match.scoreEvents.append(event)
        modelContext.insert(event)
    }

    private func undoLastSetWon() {
        guard let lastEvent = match.scoreEvents
            .filter({ $0.kind == .setWon })
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last else {
            return
        }
        match.scoreEvents.removeAll { $0.id == lastEvent.id }
        modelContext.delete(lastEvent)
    }

    private func deleteGoal(id: UUID) {
        guard let event = match.scoreEvents.first(where: { $0.id == id }) else { return }
        match.scoreEvents.removeAll { $0.id == id }
        modelContext.delete(event)
    }

    private func updateGoalTimestamp(id: UUID, time: TimeInterval) {
        guard let event = match.scoreEvents.first(where: { $0.id == id }) else { return }
        event.timestamp = time
    }

    // MARK: - PK Actions

    private func addPKKick(team: Team, isGoal: Bool, at timestamp: TimeInterval) {
        var kicks = match.pkKicks
        let order = kicks.filter { $0.team == team }.count + 1
        kicks.append(PKKick(team: team, order: order, isGoal: isGoal, timestamp: timestamp))
        match.pkKicks = kicks
    }

    private func undoLastPKKick() {
        var kicks = match.pkKicks
        guard !kicks.isEmpty else { return }
        kicks.removeLast()
        match.pkKicks = kicks
    }

    private func deletePKKick(id: UUID) {
        match.pkKicks.removeAll { $0.id == id }
    }

    private func updatePKKickTimestamp(id: UUID, time: TimeInterval) {
        var kicks = match.pkKicks
        guard let idx = kicks.firstIndex(where: { $0.id == id }) else { return }
        kicks[idx].timestamp = time
        match.pkKicks = kicks
    }

    // MARK: - Penalty Timer Actions

    private func addPenaltyTimer(team: Team, duration: TimeInterval, at timestamp: TimeInterval) {
        var timers = match.penaltyTimers
        timers.append(PenaltyTimer(team: team, timestamp: timestamp, durationSeconds: duration))
        match.penaltyTimers = timers
    }

    private func deletePenaltyTimer(id: UUID) {
        match.penaltyTimers.removeAll { $0.id == id }
    }

    private func updatePenaltyTimerTimestamp(id: UUID, time: TimeInterval) {
        var timers = match.penaltyTimers
        guard let idx = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[idx].timestamp = time
        match.penaltyTimers = timers
    }

    // MARK: - Timeout Actions

    private func startTimeout(team: Team, at timestamp: TimeInterval) {
        var list = match.timeouts
        list.append(TimeoutEvent(team: team, timestamp: timestamp))
        match.timeouts = list
    }

    private func endTimeout(id: UUID, at time: TimeInterval) {
        var list = match.timeouts
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].endTimestamp = time
        match.timeouts = list
    }

    private func deleteTimeout(id: UUID) {
        match.timeouts.removeAll { $0.id == id }
    }

    private func updateTimeoutTimestamp(id: UUID, time: TimeInterval) {
        var list = match.timeouts
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].timestamp = time
        match.timeouts = list
    }

    // MARK: - Segment Actions

    private func setSegmentStart(at index: Int, time: TimeInterval) {
        var segments = match.timerSegments
        guard index < segments.count else { return }
        segments[index].segmentStartTime = time
        // キックオフが区切り開始より前ならクリア
        if let kickoff = segments[index].timerStartTime, kickoff < time {
            segments[index].timerStartTime = nil
        }
        match.timerSegments = segments
    }

    private func setSegmentTimerStart(at index: Int, time: TimeInterval) {
        var segments = match.timerSegments
        guard index < segments.count else { return }
        segments[index].timerStartTime = time
        if let stop = segments[index].timerStopTime, stop <= time {
            segments[index].timerStopTime = nil
        }
        match.timerSegments = segments
    }

    private func setSegmentTimerStop(at index: Int, time: TimeInterval) {
        var segments = match.timerSegments
        guard index < segments.count else { return }
        guard let start = segments[index].timerStartTime, time > start else { return }
        segments[index].timerStopTime = time
        match.timerSegments = segments
    }

    private func clearSegmentTimer(at index: Int) {
        var segments = match.timerSegments
        guard index < segments.count else { return }
        segments[index].segmentStartTime = nil
        segments[index].timerStartTime = nil
        segments[index].timerStopTime = nil
        segments[index].timerStartOffset = nil
        match.timerSegments = segments
    }

    private func setSegmentOffset(at index: Int, seconds: TimeInterval) {
        var segments = match.timerSegments
        guard index < segments.count else { return }
        let clamped = max(0, seconds)
        segments[index].timerStartOffset = clamped > 0 ? clamped : nil
        match.timerSegments = segments
    }

    private func setSegmentPeriodLabel(at index: Int, label: String?) {
        var segments = match.timerSegments
        guard index < segments.count else { return }
        segments[index].periodLabel = label
        match.timerSegments = segments
    }

    private func setSegmentShowPlusPrefix(at index: Int, value: Bool) {
        var segments = match.timerSegments
        guard index < segments.count else { return }
        segments[index].showPlusPrefix = value
        match.timerSegments = segments
    }

    private func setSegmentTimerColor(at index: Int, hex: String?) {
        var segments = match.timerSegments
        guard index < segments.count else { return }
        segments[index].timerColorHex = hex
        match.timerSegments = segments
    }

    private func setSegmentTeamColor(at index: Int, team: Team, hex: String?) {
        var segments = match.timerSegments
        guard index < segments.count else { return }
        switch team {
        case .home: segments[index].homeTeamColorHex = hex
        case .away: segments[index].awayTeamColorHex = hex
        }
        match.timerSegments = segments
    }

    private func addTimerSegment() {
        var segments = match.timerSegments
        segments.append(TimerSegment())
        match.timerSegments = segments
    }

    private func addTimerSegmentWithRestart(at currentTime: TimeInterval) {
        var segments = match.timerSegments

        // 前のセグメントの最終タイマー値を計算し、試合終了を記録
        var lastTimerValue: TimeInterval = 0
        if let lastIdx = segments.indices.last {
            let prev = segments[lastIdx]
            let kickoff = prev.timerStartTime ?? prev.effectiveStartTime ?? 0
            let stop = prev.timerStopTime ?? currentTime
            let elapsed = max(0, stop - kickoff)
            let offset = prev.timerStartOffset ?? 0

            // タイムアウト分を差し引く
            var paused: TimeInterval = 0
            for timeout in match.timeouts {
                paused += timeout.pausedSeconds(from: kickoff, to: stop)
            }
            lastTimerValue = max(0, elapsed - paused) + offset

            // 前セクションの試合終了を記録
            segments[lastIdx].timerStopTime = currentTime
        }

        // 新セクション: 区切り開始 + 開始時間引き継ぎ + キックオフ開始
        var newSegment = TimerSegment()
        newSegment.segmentStartTime = currentTime  // 区切り開始
        newSegment.timerStartTime = currentTime     // キックオフ開始
        newSegment.timerStartOffset = lastTimerValue // 前セクション終了時のタイマー値
        segments.append(newSegment)
        match.timerSegments = segments
    }

    private func removeTimerSegment(at index: Int) {
        var segments = match.timerSegments
        guard segments.count > 1, index < segments.count else { return }
        segments.remove(at: index)
        match.timerSegments = segments
    }

    // MARK: - Live Stopwatch (動画なし時)

    private func startLiveTimer() {
        liveStartDate = Date()
        liveIsRunning = true
    }

    private func pauseLiveTimer() {
        guard liveIsRunning else { return }
        if let start = liveStartDate {
            liveElapsed += Date().timeIntervalSince(start)
        }
        liveStartDate = nil
        liveIsRunning = false
        liveDisplayTime = liveElapsed
    }

    private func resetLiveTimer() {
        liveIsRunning = false
        liveStartDate = nil
        liveElapsed = 0
        liveDisplayTime = 0
    }
}


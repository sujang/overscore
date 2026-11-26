import UIKit
import BackgroundTasks
import os

/// 動画の取り込みなど、時間のかかる処理を端末のロックやアプリ切り替えから守る。
///
/// 1. 自動ロックを止める（画面を点けたままにする）
/// 2. iOS 26 以降は `BGContinuedProcessingTask` を使い、手動でロックしたり他のアプリへ
///    切り替えたりしても処理を最後まで続けられるようにする。進捗はシステムのUIに表示される。
/// 3. それ以前の iOS、または 2 が使えないときは `beginBackgroundTask` で数十秒の猶予を得る。
/// 4. どれも使えなくなりアプリが一時停止されるときは、`setCancellable` で登録した転送を中断する。
///
/// 4 が必要な理由: 写真ライブラリからの受け取り中はファイルコーディネーションのクレームを保持している。
/// クレームを保持したまま一時停止されると、システムが解放を待ちきれずにアプリを強制終了する
/// （RunningBoard 0x2182BAAD）。先に転送を中断すれば、強制終了ではなく通常の一時停止になり、
/// 入力中の画面も残る。
@MainActor
final class LongRunningActivity {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OverScore",
        category: "LongRunningActivity"
    )

    /// 同時に実行中の処理の数。最後の処理が終わったときだけ自動ロックを戻す。
    private static var activeCount = 0

    /// 進捗の分母。継続処理タスクは completedUnitCount が変化しないと停止と見なすため、
    /// 小さな前進も整数で表せるよう細かく刻む。
    private nonisolated static let progressUnitCount: Int64 = 1_000_000

    /// 進捗が届かないときに表示上の進捗を少しずつ進める間隔
    private static let heartbeatInterval: TimeInterval = 5
    /// 1回の空打ちで、現在の段階の残りのうち進める割合
    private static let heartbeatStepRatio = 0.03

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isActive = false

    /// 継続処理タスクとスレッド間で共有する状態
    private let shared = SharedState()

    /// 実際の進捗（0〜1）
    private var actualFraction: Double = 0
    /// システムに報告した進捗。後戻りさせない。
    private var reportedFraction: Double = 0
    /// 現在の段階（動画1本ぶんなど）の上限。空打ちの前進はここを超えない。
    private var stageUpperBound: Double = 1
    private var lastActualChange = Date()
    private var heartbeatTimer: Timer?

    /// 一時停止前に中断する転送
    private var cancellable: Progress?
    /// 実行猶予がなくなり、転送を中断したか
    private(set) var wasInterrupted = false

    /// - Parameters:
    ///   - name: デバッグ用のタスク名
    ///   - title: iOS 26 以降でシステムの進捗表示に出すタイトル
    static func begin(name: String, title: String) -> LongRunningActivity {
        let activity = LongRunningActivity()
        activity.start(name: name, title: title)
        return activity
    }

    private func start(name: String, title: String) {
        isActive = true
        Self.activeCount += 1
        UIApplication.shared.isIdleTimerDisabled = true
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated {
                self?.backgroundTaskDidExpire()
            }
        }
        if #available(iOS 26.0, *) {
            submitContinuedProcessingTask(title: title)
        }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.heartbeat()
            }
        }
    }

    // MARK: - 進捗

    /// これから始める段階の範囲（全体に対する 0〜1）を伝える。
    /// 進捗が届かない間は、表示上の進捗をこの段階の上限に向けて少しずつ進める。
    func beginStage(upTo upperBound: Double) {
        stageUpperBound = min(max(upperBound, reportedFraction), 1)
        lastActualChange = Date()
    }

    /// 全体の実際の進捗（0〜1）を報告する。
    func updateProgress(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        if clamped > actualFraction {
            actualFraction = clamped
            lastActualChange = Date()
        }
        report(max(reportedFraction, actualFraction))
    }

    /// 継続処理タスクは進捗が一定時間変化しないと「停止」と見なされて打ち切られる。
    /// 写真ライブラリからのコピー中は途中の進捗が届かないことが多いため、
    /// 実際の進捗が止まっている間は現在の段階の上限に向けて表示上の進捗を少しずつ進める
    /// （上限には届かず、実際の進捗が届けばそちらに置き換わる）。
    private func heartbeat() {
        guard isActive, Date().timeIntervalSince(lastActualChange) >= Self.heartbeatInterval else { return }
        let remaining = stageUpperBound - reportedFraction
        guard remaining > 0 else { return }
        report(reportedFraction + remaining * Self.heartbeatStepRatio)
    }

    private func report(_ fraction: Double) {
        reportedFraction = min(fraction, 1)
        shared.setFraction(reportedFraction)
    }

    // MARK: - 中断

    /// 実行猶予がなくなったときに中断する転送を登録する。nil で解除。
    func setCancellable(_ progress: Progress?) {
        // 開始通知は MainActor へ非同期に届くため、転送がすでに終わっていれば登録しない
        if let progress, progress.isFinished || progress.isCancelled { return }
        cancellable = progress
        if wasInterrupted {
            progress?.cancel()
        }
    }

    /// 一時停止される前に、進行中の転送を中断する。
    private func interruptIfNoRuntimeLeft(reason: String) {
        let hasContinuedTask = shared.hasRunningTask
        let isForeground = UIApplication.shared.applicationState == .active
        Self.logger.notice("""
            runtime check reason=\(reason, privacy: .public) \
            foreground=\(isForeground, privacy: .public) \
            backgroundTask=\(self.backgroundTaskID != .invalid, privacy: .public) \
            continuedTask=\(hasContinuedTask, privacy: .public)
            """)
        guard isActive, !isForeground, backgroundTaskID == .invalid, !hasContinuedTask else { return }
        wasInterrupted = true
        Self.logger.notice("interrupting transfer before suspension (cancellable=\(self.cancellable != nil, privacy: .public))")
        cancellable?.cancel()
    }

    private func backgroundTaskDidExpire() {
        Self.logger.notice("background task expired")
        endBackgroundTask()
        interruptIfNoRuntimeLeft(reason: "backgroundTaskExpired")
    }

    // MARK: - 終了

    /// 処理の終了を伝える。複数回呼んでも安全。
    func end(success: Bool = true) {
        guard isActive else { return }
        isActive = false
        Self.activeCount -= 1
        if Self.activeCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        cancellable = nil
        let succeeded = success && !wasInterrupted
        if succeeded {
            report(1)
        }
        shared.complete(success: succeeded)
        endBackgroundTask()
        Self.logger.notice("activity ended success=\(succeeded, privacy: .public)")
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - BGContinuedProcessingTask (iOS 26+)

    @available(iOS 26.0, *)
    private func submitContinuedProcessingTask(title: String) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        // Info.plist の BGTaskSchedulerPermittedIdentifiers に "<bundleID>.import.*" を登録済み
        let identifier = "\(bundleID).import.\(UUID().uuidString)"

        // 継続処理タスクは起動完了後の登録が許されている。ID は毎回一意なので重複登録にならない。
        // 起動ハンドラは BGTaskScheduler のキュー（メインスレッド以外）で呼ばれる。
        // MainActor 上で作ったクロージャは MainActor 隔離と推論され、実行時チェックでクラッシュするため、
        // nonisolated な関数で作る。
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil,
            launchHandler: Self.makeLaunchHandler(shared: shared, activity: WeakActivity(self))
        )
        guard registered else {
            Self.logger.error("failed to register continued processing task")
            return
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: title,
            subtitle: String(localized: "完了するまでロックしても続行します")
        )
        // すぐに開始できない場合は待たずに諦める（beginBackgroundTask の猶予だけで続ける）
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            Self.logger.notice("submitted continued processing task")
        } catch {
            Self.logger.error("failed to submit continued processing task: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// ユーザーがシステムUIから停止した、または進捗が止まったと判断された後の処理。
    private func continuedTaskDidExpire() {
        interruptIfNoRuntimeLeft(reason: "continuedTaskExpired")
    }

    // MARK: - BGTaskScheduler から呼ばれるクロージャ
    // どちらもメインスレッド以外で呼ばれるため、MainActor に隔離されない nonisolated 関数で作る。
    // 進捗の設定と完了報告はその場（呼ばれたスレッド）で同期的に行い、
    // LongRunningActivity 本体への通知だけ MainActor へ移す。

    @available(iOS 26.0, *)
    private nonisolated static func makeLaunchHandler(
        shared: SharedState,
        activity: WeakActivity
    ) -> @Sendable (BGTask) -> Void {
        return { task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            continued.expirationHandler = makeExpirationHandler(shared: shared, activity: activity)
            shared.attach(continued)
        }
    }

    @available(iOS 26.0, *)
    private nonisolated static func makeExpirationHandler(
        shared: SharedState,
        activity: WeakActivity
    ) -> @Sendable () -> Void {
        return {
            shared.expire()
            Task { @MainActor in
                activity.value?.continuedTaskDidExpire()
            }
        }
    }

    // MARK: - スレッド間で共有する状態

    /// 継続処理タスクと進捗を保持する。BGTaskScheduler のキューと MainActor の両方から触るためロックで守る。
    private final class SharedState: @unchecked Sendable {
        private struct State {
            var task: AnyObject?
            var fraction: Double = 0
            /// タスク開始前に処理が終わっていた場合の結果
            var completedResult: Bool?
            var lastLoggedFraction: Double = -1
        }

        private let lock = OSAllocatedUnfairLock(uncheckedState: State())

        var hasRunningTask: Bool {
            lock.withLockUnchecked { $0.task != nil }
        }

        @available(iOS 26.0, *)
        func attach(_ task: BGContinuedProcessingTask) {
            let pending: Bool? = lock.withLockUnchecked { state in
                if let result = state.completedResult {
                    return result
                }
                state.task = task
                LongRunningActivity.apply(state.fraction, to: task.progress)
                return nil
            }
            if let pending {
                // 処理がタスク開始より先に終わっていた
                LongRunningActivity.apply(1, to: task.progress)
                task.setTaskCompleted(success: pending)
                LongRunningActivity.logger.notice("continued task started after activity ended")
            } else {
                LongRunningActivity.logger.notice("continued task attached")
            }
        }

        func setFraction(_ fraction: Double) {
            lock.withLockUnchecked { state in
                state.fraction = fraction
                if #available(iOS 26.0, *), let task = state.task as? BGContinuedProcessingTask {
                    LongRunningActivity.apply(fraction, to: task.progress)
                    // 診断用。5% ごとに記録する
                    if fraction - state.lastLoggedFraction >= 0.05 {
                        state.lastLoggedFraction = fraction
                        LongRunningActivity.logger.notice("""
                            progress reported \(task.progress.completedUnitCount, privacy: .public)/\
                            \(task.progress.totalUnitCount, privacy: .public)
                            """)
                    }
                }
            }
        }

        func expire() {
            let task: AnyObject? = lock.withLockUnchecked { state in
                defer { state.task = nil }
                return state.task
            }
            LongRunningActivity.logger.notice("continued task expired (attached=\(task != nil, privacy: .public))")
            if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
                task.setTaskCompleted(success: false)
            }
        }

        func complete(success: Bool) {
            let task: AnyObject? = lock.withLockUnchecked { state in
                state.completedResult = success
                defer { state.task = nil }
                return state.task
            }
            if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
                if success {
                    LongRunningActivity.apply(1, to: task.progress)
                }
                task.setTaskCompleted(success: success)
            }
        }
    }

    private nonisolated static func apply(_ fraction: Double, to progress: Progress) {
        progress.totalUnitCount = progressUnitCount
        progress.completedUnitCount = Int64(fraction * Double(progressUnitCount))
    }
}

/// スレッドをまたいで LongRunningActivity を弱参照で渡すための入れ物。
/// value へは MainActor 上でのみアクセスする。
private final class WeakActivity: @unchecked Sendable {
    weak var value: LongRunningActivity?
    init(_ value: LongRunningActivity) { self.value = value }
}

import UIKit
import BackgroundTasks
import os

/// 動画の取り込みなど、時間のかかる処理の間の端末ロック対策と進捗表示。
///
/// 1. 自動ロックを止める（画面を点けたままにする）
/// 2. 手動でロック・アプリ切り替えされた場合は `beginBackgroundTask` で数十秒の猶予を得る。
///    猶予切れ時は必ず endBackgroundTask する（終了しないとシステムに強制終了される）。
/// 3. iOS 26 以降は `BGContinuedProcessingTask` を使い、ロック画面などのシステムUIに進捗を表示する。
///
/// 既知の制約（v1.3.9 時点、iOS 27.2 実機で確認）:
/// 写真ピッカーからの受け取り中に手動ロックなどで猶予（約30秒）が切れると、アプリは強制終了される
/// （RunningBoard 0x2182BAAD）。PhotosPicker が内部で PhotosFileProvider のファイルコーディネーション
/// クレームを保持しており、一時停止時にその解放待ちがタイムアウトするため。
/// 次の対策はいずれも効果がなかった:
/// - loadTransferable が返す Progress の cancel()（クレームは解放されない）
/// - BGContinuedProcessingTask（タスク動作中・判定「続行可」でも猶予切れで一時停止される）
/// そのため 3 は進捗表示のためだけに使っている。
/// 防ぐには PHAssetResourceManager で直接読み出すなど、受け取り方式の変更が必要。
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

    private func backgroundTaskDidExpire() {
        Self.logger.notice("background task expired")
        endBackgroundTask()
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
        if success {
            report(1)
        }
        shared.complete(success: success)
        endBackgroundTask()
        Self.logger.notice("activity ended success=\(success, privacy: .public)")
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
            launchHandler: Self.makeLaunchHandler(shared: shared)
        )
        guard registered else {
            Self.logger.error("failed to register continued processing task")
            return
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: title,
            subtitle: String(localized: "写真ライブラリから取り込んでいます")
        )
        // すぐに開始できない場合は待たずに諦める（進捗表示なしで取り込みは続ける）
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            Self.logger.notice("submitted continued processing task")
        } catch {
            Self.logger.error("failed to submit continued processing task: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - BGTaskScheduler から呼ばれるクロージャ
    // どちらもメインスレッド以外で呼ばれるため、MainActor に隔離されない nonisolated 関数で作る。
    // 進捗の設定と完了報告はその場（呼ばれたスレッド）で同期的に行う。

    @available(iOS 26.0, *)
    private nonisolated static func makeLaunchHandler(
        shared: SharedState
    ) -> @Sendable (BGTask) -> Void {
        return { task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            continued.expirationHandler = makeExpirationHandler(shared: shared)
            shared.attach(continued)
        }
    }

    @available(iOS 26.0, *)
    private nonisolated static func makeExpirationHandler(
        shared: SharedState
    ) -> @Sendable () -> Void {
        // ユーザーがシステムUIから停止した、または進捗が止まったと判断された。
        // 取り込み自体は beginBackgroundTask の猶予の範囲で続ける。
        return {
            shared.expire()
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


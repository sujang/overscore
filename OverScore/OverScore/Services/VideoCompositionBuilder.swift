import AVFoundation
import CoreGraphics

enum VideoCompositionBuilder {

    struct Result {
        let composition: AVMutableComposition
        let videoSize: CGSize
        let duration: CMTime
        let segmentTransforms: [(track: AVMutableCompositionTrack, transform: CGAffineTransform, naturalSize: CGSize)]
        /// 元動画のフレーム間隔。29.97fps のようなドロップフレームレートを
        /// 1001/30000 の有理数のまま保持する（整数丸めによるコマ重複を防ぐため）。
        let frameDuration: CMTime

        var nominalFrameRate: Float {
            let seconds = frameDuration.seconds
            return seconds > 0 ? Float(1.0 / seconds) : 30.0
        }
    }

    enum BuildError: LocalizedError {
        case noURLs
        case noVideoTrack(URL)
        case trackCreationFailed

        var errorDescription: String? {
            switch self {
            case .noURLs:
                return String(localized: "動画URLが指定されていません")
            case .noVideoTrack(let url):
                return String(localized: "動画トラックが見つかりません: \(url.lastPathComponent)")
            case .trackCreationFailed:
                return String(localized: "コンポジショントラックの作成に失敗しました")
            }
        }
    }

    // MARK: - Build Composition

    static func build(from urls: [URL]) async throws -> Result {
        guard !urls.isEmpty else { throw BuildError.noURLs }

        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw BuildError.trackCreationFailed
        }

        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var currentTime = CMTime.zero
        var referenceSize: CGSize?
        var shortestFrameDuration: CMTime?
        var segments: [(track: AVMutableCompositionTrack, transform: CGAffineTransform, naturalSize: CGSize)] = []

        for url in urls {
            let asset = AVURLAsset(url: url)

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = videoTracks.first else {
                throw BuildError.noVideoTrack(url)
            }

            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

            try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: currentTime)

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = audioTracks.first, let audioTrack = compositionAudioTrack {
                try audioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: currentTime)
            }

            let corrected = correctedSize(naturalSize: naturalSize, transform: preferredTransform)
            if referenceSize == nil {
                referenceSize = corrected
            }

            // 複数動画を連結する場合、最もフレームレートの高い素材に合わせる。
            // 低い方に合わせるとその素材のコマが間引かれてカクつくため。
            let segmentFrameDuration = try await detectFrameDuration(of: sourceVideoTrack, in: asset)
            if let current = shortestFrameDuration {
                shortestFrameDuration = CMTimeMinimum(current, segmentFrameDuration)
            } else {
                shortestFrameDuration = segmentFrameDuration
            }

            segments.append((
                track: compositionVideoTrack,
                transform: preferredTransform,
                naturalSize: naturalSize
            ))

            currentTime = CMTimeAdd(currentTime, duration)
        }

        let videoSize = referenceSize ?? CGSize(width: 1920, height: 1080)
        let frameDuration = shortestFrameDuration ?? defaultFrameDuration

        return Result(
            composition: composition,
            videoSize: videoSize,
            duration: currentTime,
            segmentTransforms: segments,
            frameDuration: frameDuration
        )
    }

    // MARK: - Video Composition (Layer Instructions)

    static func makeVideoComposition(
        result: Result,
        videoLayer: CALayer,
        parentLayer: CALayer
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = result.videoSize
        // オーバーレイ合成は重いので高フレームレート素材は 60fps に丸める
        videoComposition.frameDuration = clampedFrameDuration(result.frameDuration)
        applySDRColorProperties(to: videoComposition)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: result.duration)

        // 最初のセグメントの transform を使用（全セグメント同一トラック）
        if let first = result.segmentTransforms.first {
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: first.track)
            layerInstruction.setTransform(
                correctedTransform(first.transform, naturalSize: first.naturalSize),
                at: .zero
            )
            instruction.layerInstructions = [layerInstruction]
        }

        videoComposition.instructions = [instruction]
        return videoComposition
    }

    // MARK: - Video Composition (Without Overlay)

    static func makeVideoCompositionWithoutOverlay(
        result: Result
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = result.videoSize
        videoComposition.frameDuration = result.frameDuration
        applySDRColorProperties(to: videoComposition)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: result.duration)

        if let first = result.segmentTransforms.first {
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: first.track)
            layerInstruction.setTransform(
                correctedTransform(first.transform, naturalSize: first.naturalSize),
                at: .zero
            )
            instruction.layerInstructions = [layerInstruction]
        }

        videoComposition.instructions = [instruction]
        return videoComposition
    }

    // MARK: - Color

    /// 出力を Rec.709 (SDR) に固定する。
    /// HDR (HLG / Dolby Vision) 素材はここで SDR にトーンマッピングされ、H.264 出力やスコアボードの色と整合する。
    private static func applySDRColorProperties(to videoComposition: AVMutableVideoComposition) {
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
    }

    // MARK: - Passthrough Check

    /// 再エンコードせずに MP4 へ連結出力してよいかを判定する。
    /// 全素材が H.264・SDR・同一解像度・同一向きの場合のみ true。
    /// HEVC / ProRes / HDR / 形式混在の素材は、互換性のため H.264 で再エンコードする。
    static func canPassthrough(urls: [URL]) async -> Bool {
        var reference: (size: CGSize, transform: CGAffineTransform)?

        for url in urls {
            let asset = AVURLAsset(url: url)
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { return false }
                let (formatDescriptions, characteristics, naturalSize, transform) = try await track.load(
                    .formatDescriptions, .mediaCharacteristics, .naturalSize, .preferredTransform
                )
                let isH264 = !formatDescriptions.isEmpty && formatDescriptions.allSatisfy {
                    CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264
                }
                guard isH264, !characteristics.contains(.containsHDRVideo) else { return false }

                if let reference {
                    guard reference.size == naturalSize, reference.transform == transform else { return false }
                } else {
                    reference = (naturalSize, transform)
                }
            } catch {
                return false
            }
        }
        return true
    }

    // MARK: - Frame Rate Detection

    static let defaultFrameDuration = CMTime(value: 1, timescale: 30)

    /// 実測に使うサンプル数の上限。240サンプルは 30fps なら約8秒・240fps なら約1秒分。
    private static let frameSampleBudget = 240
    /// 実測値を信頼するのに必要な最小サンプル数。
    /// サンプル長はサンプルテーブルの厳密値でノイズを含まないため、
    /// 3つあれば最頻値が決まる。短いクリップでも（メタデータが誤っていることの多い）
    /// nominalFrameRate に頼らず実測できるよう、あえて低く設定している。
    private static let minimumFrameSampleCount = 3
    /// 標準フレームレートへスナップする際の相対許容差（0.5%）。
    /// 絶対値ではなく相対値で判定することで、29.97 と 30（0.1%差）を取り違えず、
    /// 240fps にも同じ基準を適用できる。
    private static let standardRateRelativeTolerance = 0.005
    /// オーバーレイ合成時に許容する最大フレームレート。
    /// 60 と 59.94 はそのまま通し、120/240 のスローモー素材だけを間引くための閾値。
    private static let maxOverlayFrameRate = 60.5
    /// AVAssetReader フォールバックで走査する先頭の時間範囲。
    private static let readerScanDuration = CMTime(value: 20, timescale: 1)

    /// 標準的なフレームレートと、それに対応する正確なフレーム間隔。
    /// 29.97 / 59.94 などのドロップフレームレートは 1001/30000 形式の有理数で保持する。
    /// 30 に丸めてしまうと約1000フレームに1枚コマが重複し、周期的なカクつきの原因になる。
    private static let standardFrameDurations: [(rate: Double, duration: CMTime)] = [
        (24000.0 / 1001.0, CMTime(value: 1001, timescale: 24000)),
        (24, CMTime(value: 1, timescale: 24)),
        (25, CMTime(value: 1, timescale: 25)),
        (30000.0 / 1001.0, CMTime(value: 1001, timescale: 30000)),
        (30, CMTime(value: 1, timescale: 30)),
        (50, CMTime(value: 1, timescale: 50)),
        (60000.0 / 1001.0, CMTime(value: 1001, timescale: 60000)),
        (60, CMTime(value: 1, timescale: 60)),
        (100, CMTime(value: 1, timescale: 100)),
        (120000.0 / 1001.0, CMTime(value: 1001, timescale: 120000)),
        (120, CMTime(value: 1, timescale: 120)),
        (240, CMTime(value: 1, timescale: 240))
    ]

    /// 元動画のフレーム間隔を検出する。
    ///
    /// nominalFrameRate は写真アプリでトリムした動画（edit list 付き）やVFR素材で
    /// 実値からずれた値（例: 30FPS素材なのに 29.4 や 15.79）を返し、
    /// minFrameDuration は「最短フレーム長」であって平均ではない。
    /// どちらも単独ではフレームレートを決められないため、
    /// 実際のサンプルのタイミングから実測し、メタデータは実測できないときだけ使う。
    static func detectFrameDuration(of track: AVAssetTrack, in asset: AVAsset) async throws -> CMTime {
        if let measured = measuredFrameDuration(of: track, in: asset) {
            return measured
        }
        return try await metadataFrameDuration(of: track)
    }

    // MARK: - Measurement

    /// サンプルのタイミングを実測してフレーム間隔を求める。実測できなければ nil。
    static func measuredFrameDuration(of track: AVAssetTrack, in asset: AVAsset) -> CMTime? {
        if let durations = sampleDurationsUsingCursor(of: track),
           durations.count >= minimumFrameSampleCount {
            return robustFrameDuration(from: durations)
        }
        if let durations = sampleDurationsUsingReader(of: track, in: asset),
           durations.count >= minimumFrameSampleCount {
            return robustFrameDuration(from: durations)
        }
        return nil
    }

    /// サンプルテーブルだけを辿ってフレーム長を取得する。メディアデータは一切読まない。
    /// デコード順に走査するが currentSampleDuration は並び順に依存しないため、
    /// Bフレームがあっても並べ替えは不要。
    private static func sampleDurationsUsingCursor(of track: AVAssetTrack) -> [CMTime]? {
        guard let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else { return nil }

        var durations: [CMTime] = []
        durations.reserveCapacity(frameSampleBudget)

        repeat {
            let duration = cursor.currentSampleDuration
            // MPEG-2 TS などのストリーミング形式では kCMTimeIndefinite が返る
            if duration.isNumeric && duration.value > 0 {
                durations.append(duration)
            }
            if durations.count >= frameSampleBudget { break }
        } while cursor.stepInDecodeOrder(byCount: 1) == 1

        return durations.isEmpty ? nil : durations
    }

    /// AVSampleCursor を提供できない素材向けのフォールバック。
    /// outputSettings: nil はパススルー（デコードなし）だが、サンプルデータ自体は読まれる。
    /// AVMutableComposition 由来のトラックに使うと未定義動作になるため、
    /// 呼び出し側はソースの AVURLAsset のトラックだけを渡すこと。
    private static func sampleDurationsUsingReader(of track: AVAssetTrack, in asset: AVAsset) -> [CMTime]? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        // track が asset に属していない場合は canAdd が false（add すると例外）
        guard reader.canAdd(output) else { return nil }
        reader.add(output)

        // timeRange は startReading() より前に設定しないと例外になる
        reader.timeRange = CMTimeRange(start: .zero, duration: readerScanDuration)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }

        var durations: [CMTime] = []
        var presentationTimes: [CMTime] = []
        durations.reserveCapacity(frameSampleBudget)
        presentationTimes.reserveCapacity(frameSampleBudget)

        while presentationTimes.count < frameSampleBudget {
            guard let buffer = output.copyNextSampleBuffer() else { break }
            if CMSampleBufferGetNumSamples(buffer) == 1 {
                let duration = CMSampleBufferGetDuration(buffer)
                if duration.isNumeric && duration.value > 0 {
                    durations.append(duration)
                }
            }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(buffer)
            if presentationTime.isNumeric {
                presentationTimes.append(presentationTime)
            }
        }

        if durations.count >= minimumFrameSampleCount {
            return durations
        }

        // duration が取れない素材は PTS の差分で代用する。
        // パススルー出力はデコード順なので、Bフレームを考慮して並べ替えてから差分を取る。
        guard presentationTimes.count > minimumFrameSampleCount else { return nil }
        let sorted = presentationTimes.sorted { CMTimeCompare($0, $1) < 0 }
        var intervals: [CMTime] = []
        intervals.reserveCapacity(sorted.count - 1)
        for index in 1..<sorted.count {
            let interval = CMTimeSubtract(sorted[index], sorted[index - 1])
            if interval.isNumeric && interval.value > 0 {
                intervals.append(interval)
            }
        }
        return intervals.isEmpty ? nil : intervals
    }

    // MARK: - Statistics

    /// ジッタ・コマ落ち・可変フレームレートに強い代表フレーム長を返す。
    /// 1) 最頻フレーム長（mode）で本来の周期を掴む
    /// 2) mode から離れすぎた「まれな」フレーム長を外れ値として捨てる
    /// 3) 残りの平均をレートとする
    /// 4) 標準フレームレート近傍なら正確な有理数（1001/30000 など）にスナップする
    ///
    /// 平均を使うのは、1フレームの長さがタイムスケールで割り切れない素材では
    /// 隣接する2値にディザリングされるため。
    /// 例: 240fps を timescale 600 に入れると 600/240 = 2.5 が表現できず
    /// 2/600 と 3/600 が交互に並ぶ。中央値や最頻値だと 300fps / 200fps になるが、
    /// 平均なら 2.5/600 = 240fps と正しく求まる。
    static func robustFrameDuration(from durations: [CMTime]) -> CMTime? {
        let valid = durations.filter { $0.isNumeric && $0.value > 0 && $0.seconds > 0 }
        guard !valid.isEmpty else { return nil }

        var counts: [Int64: (duration: CMTime, count: Int)] = [:]
        for duration in valid {
            let key = frameDurationKey(duration)
            if let existing = counts[key] {
                counts[key] = (existing.duration, existing.count + 1)
            } else {
                counts[key] = (duration, 1)
            }
        }
        guard let mode = modeFrameDuration(counts), mode.seconds > 0 else { return nil }

        // 外れ値かどうかは「mode との比率」だけでは決められない。
        // 240fps@timescale600 のディザリング（2 と 3 ティック）は 1.5倍の開きがあり、
        // 30fps素材に紛れ込む 1/60 のフレーム（0.5倍）と比率では区別がつかない。
        // 両者を分けるのは出現頻度で、ディザリングは両方の値が高頻度に現れるのに対し、
        // 誤判定の原因になる 1/60 フレームやコマ落ちはごく少数しか現れない。
        //
        // したがって次のどちらかを満たすものだけを残す:
        //   a) mode との差が15%以内（29.97fps@timescale600 の 20/21 ティックなど）
        //   b) 全サンプルの20%以上を占める（真のディザリングや可変フレームレート）
        let significantCount = max(2, valid.count / 5)
        let kept = valid.filter { duration in
            let ratio = duration.seconds / mode.seconds
            if abs(ratio - 1.0) <= 0.15 { return true }
            return (counts[frameDurationKey(duration)]?.count ?? 0) >= significantCount
        }
        guard kept.count >= minimumFrameSampleCount else {
            return snapToStandardFrameDuration(mode)
        }

        var total = CMTime.zero
        for duration in kept {
            total = CMTimeAdd(total, duration)
        }
        guard total.isNumeric, total.seconds > 0 else {
            return snapToStandardFrameDuration(mode)
        }

        let averageRate = Double(kept.count) / total.seconds
        if let standard = nearestStandardFrameDuration(
            for: averageRate,
            relativeTolerance: standardRateRelativeTolerance
        ) {
            return standard
        }

        // 標準値に該当しない場合は素材のタイミングを有理数のまま維持する
        let average = CMTimeMultiplyByRatio(total, multiplier: 1, divisor: Int32(kept.count))
        return (average.isNumeric && average.value > 0) ? average : mode
    }

    /// フレーム長をマイクロ秒に丸めたグループ化キー。
    /// タイムスケールが異なるサンプルが混在しても同じ長さなら同じキーになる。
    static func frameDurationKey(_ duration: CMTime) -> Int64 {
        Int64((duration.seconds * 1_000_000).rounded())
    }

    /// 最も出現回数の多いフレーム長を返す。同数なら短い方を採る。
    static func modeFrameDuration(_ counts: [Int64: (duration: CMTime, count: Int)]) -> CMTime? {
        var best: (duration: CMTime, count: Int)?
        for (_, entry) in counts {
            guard let current = best else {
                best = entry
                continue
            }
            if entry.count > current.count
                || (entry.count == current.count && entry.duration.seconds < current.duration.seconds) {
                best = entry
            }
        }
        return best?.duration
    }

    /// 指定フレームレートに最も近い標準フレーム間隔を返す。相対誤差が許容範囲外なら nil。
    static func nearestStandardFrameDuration(for rate: Double, relativeTolerance: Double) -> CMTime? {
        guard rate > 0 else { return nil }

        var best: (duration: CMTime, difference: Double)?
        for standard in standardFrameDurations {
            let difference = abs(standard.rate - rate)
            if let current = best, current.difference <= difference { continue }
            best = (standard.duration, difference)
        }

        guard let best, best.difference / rate <= relativeTolerance else { return nil }
        return best.duration
    }

    /// 標準フレームレート近傍ならスナップし、そうでなければ元の値をそのまま返す。
    static func snapToStandardFrameDuration(_ duration: CMTime) -> CMTime {
        guard duration.isNumeric, duration.seconds > 0 else { return duration }
        return nearestStandardFrameDuration(
            for: 1.0 / duration.seconds,
            relativeTolerance: standardRateRelativeTolerance
        ) ?? duration
    }

    /// オーバーレイ合成時のフレームレート上限を適用する。
    /// 240fps などのスローモー素材をそのまま合成すると書き出し時間とファイルサイズが
    /// 現実的でなくなるため、60fps 以下に収まるまでフレーム長を2倍にしていく。
    /// 割り算ではなく整数倍で間引くので、ドロップフレーム系も有理数の正確さを保ったまま
    /// （119.88 → 59.94）落とせる。オーバーレイなしの passthrough 書き出しは対象外。
    static func clampedFrameDuration(_ frameDuration: CMTime) -> CMTime {
        guard frameDuration.isNumeric, frameDuration.seconds > 0 else { return frameDuration }

        var result = frameDuration
        while result.seconds > 0, 1.0 / result.seconds > maxOverlayFrameRate {
            let doubled = CMTime(value: result.value * 2, timescale: result.timescale)
            guard doubled.isNumeric, doubled.seconds > result.seconds else { break }
            result = doubled
        }
        return result
    }

    // MARK: - Metadata Fallback

    /// 実測できない素材向けのフォールバック。
    /// ここでも max(nominal, 1/minFrameDuration) は取らない。
    /// minFrameDuration は最短フレーム長なので、1コマ短いフレームが混ざっているだけで
    /// 30fps 素材が 60fps に化けるため。
    private static func metadataFrameDuration(of track: AVAssetTrack) async throws -> CMTime {
        let nominal = Double(try await track.load(.nominalFrameRate))
        let minFrameDuration = try await track.load(.minFrameDuration)
        let hasMinFrameDuration = minFrameDuration.isNumeric && minFrameDuration.seconds > 0
        let minFrameDurationRate = hasMinFrameDuration ? 1.0 / minFrameDuration.seconds : 0

        // 4K iPhone素材などで nominal が実値の半分以下に報告される既知のケース
        // （例: 30FPS素材なのに 15.79）だけ minFrameDuration を優先する。
        // 閾値を 20fps で切ることで、30fps 素材が 60fps に引き上げられる誤りは起こらない。
        if nominal > 0, nominal < 20, minFrameDurationRate >= nominal * 1.5,
           let standard = nearestStandardFrameDuration(for: minFrameDurationRate, relativeTolerance: 0.01) {
            return standard
        }

        if nominal > 0 {
            if let standard = nearestStandardFrameDuration(for: nominal, relativeTolerance: 0.01) {
                return standard
            }
            if nominal < 1000 {
                return CMTime(value: 1000, timescale: Int32((nominal * 1000).rounded()))
            }
        }

        if hasMinFrameDuration {
            return snapToStandardFrameDuration(minFrameDuration)
        }
        return defaultFrameDuration
    }

    // MARK: - Transform Handling

    static func correctedSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let isRotated = abs(transform.b) == 1 && abs(transform.c) == 1
        if isRotated {
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        }
        return naturalSize
    }

    static func correctedTransform(_ transform: CGAffineTransform, naturalSize: CGSize) -> CGAffineTransform {
        let a = transform.a
        let b = transform.b
        let c = transform.c
        let d = transform.d

        // 90° clockwise (common for portrait iPhone videos)
        if a == 0 && b == 1 && c == -1 && d == 0 {
            return CGAffineTransform(translationX: naturalSize.height, y: 0)
                .rotated(by: .pi / 2)
        }

        // 90° counter-clockwise
        if a == 0 && b == -1 && c == 1 && d == 0 {
            return CGAffineTransform(translationX: 0, y: naturalSize.width)
                .rotated(by: -.pi / 2)
        }

        // 180° rotation
        if a == -1 && b == 0 && c == 0 && d == -1 {
            return CGAffineTransform(translationX: naturalSize.width, y: naturalSize.height)
                .rotated(by: .pi)
        }

        return .identity
    }
}

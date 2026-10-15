// App Store 用スクリーンショットを生成する。
//
// 使い方（リポジトリのルートで実行）:
//   swift scripts/make_appstore_screenshots.swift [言語コード...]
//   例: swift scripts/make_appstore_screenshots.swift ja
//
// 元画像: AppStore/images/{iPhone,iPad}/*.PNG（実機のスクリーンショット）
// 出力:   AppStore/screenshots/<言語>/{iPhone_6.9,iPad_13}/NN.png
//         AppStore/screenshots/header/header_21x9.png（プロダクトページのヘッダー、言語共通）
//
// https://developer.apple.com/app-store/asset-best-practices/ に沿って:
// - 実際の UI を使い、最も伝えたい機能から順に並べる
// - キャッチコピーは画面を補う短いフレーズにし、言語ごとに用意する
// - 価格・URL・著作権表記・他社ロゴを含めない（撮影機材のロゴはぼかしではなく周囲の模様で消す）
// - 中央に焦点を置き、端で切れても意味が通るようにする

import AppKit
import CoreImage
import CoreText

// MARK: - 設定

struct Caption {
    let headline: String
    let subline: String
}

struct Fill {
    /// 塗りつぶす範囲（元画像のピクセル座標、左上原点）
    let rect: CGRect
    /// 塗る色を取る位置（同じ座標系）
    let sample: CGPoint
}

/// iPad の撮影時に右下へ写り込んだインジケータ。スコア表示の「1」に近いので2つに分けて塗る。
let iPadIndicatorFills = [
    Fill(rect: CGRect(x: 2234, y: 1432, width: 32, height: 52), sample: CGPoint(x: 2250, y: 1426)),
    Fill(rect: CGRect(x: 2212, y: 1467, width: 24, height: 17), sample: CGPoint(x: 2206, y: 1480)),
]

struct Shot {
    /// AppStore/images/<device>/ 内のファイル名
    let file: String
    /// 消したい撮影機材ロゴの範囲（元画像のピクセル座標、左上原点）
    let logoRects: [CGRect]
    /// 指定位置の色で塗りつぶす範囲（撮影時に写り込んだインジケータなど）
    var fills: [Fill] = []
    /// 言語コード → キャッチコピー
    let captions: [String: Caption]
}

struct Device {
    let name: String
    let sourceDir: String
    let canvas: CGSize
    /// 元画像の上端から切り落とす高さ（ステータスバー）
    let statusBarHeight: CGFloat
    /// 画面画像の幅（キャンバスに対して）
    let screenWidth: CGFloat
    /// 画面画像の上端の位置
    let screenTop: CGFloat
    let cornerRadius: CGFloat
    let headlineSize: CGFloat
    let sublineSize: CGFloat
    let captionTop: CGFloat
    let shots: [Shot]
}

/// 同じ訴求を iPhone / iPad で共有する
enum Message {
    static let overlay: [String: Caption] = [
        "ja": Caption(headline: "撮った試合を、中継風に。", subline: "動画にスコアボードを重ねるだけ"),
        "en": Caption(headline: "Your game, broadcast style.", subline: "Add a scoreboard to any match video"),
        "ko": Caption(headline: "찍은 경기를 중계처럼.", subline: "영상에 스코어보드를 얹기만 하면 끝"),
        "zh-Hans": Caption(headline: "比赛视频，秒变直播风", subline: "只需在视频上叠加记分牌"),
    ]
    static let export: [String: Caption] = [
        "ja": Caption(headline: "MP4でそのまま共有", subline: "写真に保存してチームにシェア"),
        "en": Caption(headline: "Share as MP4", subline: "Save to Photos and send it to your team"),
        "ko": Caption(headline: "MP4로 바로 공유", subline: "사진에 저장하고 팀과 나누기"),
        "zh-Hans": Caption(headline: "导出 MP4 直接分享", subline: "保存到照片，分享给队友"),
    ]
    static let design: [String: Caption] = [
        "ja": Caption(headline: "デザインは自由自在", subline: "テーマ・色・位置・サイズを調整"),
        "en": Caption(headline: "Make it yours", subline: "Adjust theme, colors, position, and size"),
        "ko": Caption(headline: "디자인은 자유롭게", subline: "테마·색상·위치·크기 조정"),
        "zh-Hans": Caption(headline: "设计随心调整", subline: "主题、颜色、位置、大小皆可调"),
    ]
    static let periods: [String: Caption] = [
        "ja": Caption(headline: "前半も後半も延長も", subline: "ピリオドごとにタイマーを記録"),
        "en": Caption(headline: "Every half, every period", subline: "Keep the clock for each period"),
        "ko": Caption(headline: "전반도 후반도 연장도", subline: "피리어드마다 타이머 기록"),
        "zh-Hans": Caption(headline: "上下半场与加时", subline: "按时段记录比赛计时"),
    ]
    static let timeline: [String: Caption] = [
        "ja": Caption(headline: "試合の流れがひと目で", subline: "得点とピリオドをタイムラインに"),
        "en": Caption(headline: "The whole game at a glance", subline: "Goals and periods on one timeline"),
        "ko": Caption(headline: "경기 흐름을 한눈에", subline: "득점과 피리어드를 타임라인으로"),
        "zh-Hans": Caption(headline: "比赛进程一目了然", subline: "进球与时段尽在时间轴"),
    ]
}

let devices: [Device] = [
    Device(
        name: "iPhone_6.9",
        sourceDir: "iPhone",
        canvas: CGSize(width: 1320, height: 2868),
        statusBarHeight: 150,
        screenWidth: 1060,
        screenTop: 640,
        cornerRadius: 64,
        headlineSize: 104,
        sublineSize: 54,
        captionTop: 230,
        shots: [
            Shot(file: "IMG_8980.PNG", logoRects: [CGRect(x: 1012, y: 955, width: 162, height: 53)], captions: Message.overlay),
            Shot(file: "IMG_8984.PNG", logoRects: [CGRect(x: 979, y: 952, width: 152, height: 53)], captions: Message.export),
            Shot(file: "IMG_8979.PNG", logoRects: [CGRect(x: 984, y: 1078, width: 146, height: 47)], captions: Message.design),
            Shot(file: "IMG_8983.PNG", logoRects: [CGRect(x: 1012, y: 955, width: 162, height: 53)], captions: Message.periods),
            Shot(file: "IMG_8981.PNG", logoRects: [CGRect(x: 949, y: 998, width: 137, height: 47)], captions: Message.timeline),
        ]
    ),
    Device(
        name: "iPad_13",
        sourceDir: "iPad",
        canvas: CGSize(width: 2752, height: 2064),
        statusBarHeight: 66,
        screenWidth: 2260,
        screenTop: 520,
        cornerRadius: 56,
        headlineSize: 116,
        sublineSize: 60,
        captionTop: 150,
        shots: [
            Shot(file: "IMG_2033.PNG", logoRects: [CGRect(x: 1370, y: 1096, width: 210, height: 71)], fills: iPadIndicatorFills, captions: Message.overlay),
            Shot(file: "IMG_2038.PNG", logoRects: [CGRect(x: 1746, y: 1098, width: 224, height: 72)], fills: iPadIndicatorFills, captions: Message.export),
            Shot(file: "IMG_2032.PNG", logoRects: [CGRect(x: 1500, y: 835, width: 147, height: 47)], fills: iPadIndicatorFills, captions: Message.design),
            Shot(file: "IMG_2035.PNG", logoRects: [], fills: iPadIndicatorFills, captions: Message.timeline),
        ]
    ),
]

/// アプリのアクセントカラー（AccentColor: #349159）を基調にしたグラデーション
let backgroundTop = CGColor(srgbRed: 0.204, green: 0.569, blue: 0.349, alpha: 1)
let backgroundBottom = CGColor(srgbRed: 0.098, green: 0.329, blue: 0.196, alpha: 1)

let fontNames: [String: (headline: String, subline: String)] = [
    "ja": ("HiraginoSans-W8", "HiraginoSans-W6"),
    "en": ("HiraginoSans-W8", "HiraginoSans-W6"),
    "ko": ("AppleSDGothicNeo-Heavy", "AppleSDGothicNeo-Bold"),
    "zh-Hans": ("PingFangSC-Semibold", "PingFangSC-Medium"),
]

// MARK: - 画像処理

let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func loadImage(_ url: URL) -> CIImage {
    guard let image = CIImage(contentsOf: url) else { fatalError("読み込めません: \(url.path)") }
    return image
}

/// ロゴの範囲を、すぐ左隣の同じ高さの模様で上書きする。縁はぼかしてなじませる。
/// Core Image は左下原点なので、左上原点の rect を変換して扱う。
func removeLogos(from image: CIImage, rects: [CGRect]) -> CIImage {
    let height = image.extent.height
    var result = image
    for logoRect in rects {
        // ロゴの縁取りの影まで含めて消す
        let rect = logoRect.insetBy(dx: -8, dy: -8)
        let target = CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        let sourceOffset = rect.width + 24
        let patch = result
            .cropped(to: target.offsetBy(dx: -sourceOffset, dy: 0))
            .transformed(by: CGAffineTransform(translationX: sourceOffset, y: 0))

        let feather: CGFloat = 10
        let mask = CIImage(color: .white)
            .cropped(to: target.insetBy(dx: feather, dy: feather))
            .applyingGaussianBlur(sigma: feather / 2)
            .cropped(to: target)

        result = patch.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: result,
            kCIInputMaskImageKey: mask,
        ]).cropped(to: image.extent)
    }
    return result
}

/// 範囲を、指定位置の色で塗りつぶす
func fill(_ image: CIImage, fills: [Fill]) -> CIImage {
    let height = image.extent.height
    var result = image
    for fill in fills {
        let rect = fill.rect
        let target = CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        let sample = CGRect(x: fill.sample.x, y: height - fill.sample.y - 1, width: 1, height: 1)
        let color = result.cropped(to: sample).clampedToExtent().cropped(to: target)
        result = color.composited(over: result).cropped(to: image.extent)
    }
    return result
}

func cgImage(_ image: CIImage) -> CGImage {
    guard let cg = ciContext.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB) else {
        fatalError("CGImage を作れません")
    }
    return cg
}

func drawText(_ text: String, fontName: String, size: CGFloat, color: CGColor, centerX: CGFloat, top: CGFloat,
              maxWidth: CGFloat, in context: CGContext, canvasHeight: CGFloat) -> CGFloat {
    var fontSize = size
    var line: CTLine
    var bounds: CGRect
    // 長い言語でもはみ出さないよう、幅に収まるまで縮める
    repeat {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        fontSize -= 2
    } while bounds.width > maxWidth && fontSize > size * 0.6

    let font = CTFontCreateWithName(fontName as CFString, fontSize + 2, nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let baseline = canvasHeight - top - ascent
    context.textPosition = CGPoint(x: centerX - bounds.width / 2 - bounds.minX, y: baseline)
    CTLineDraw(line, context)
    return ascent + descent
}

func render(shot: Shot, device: Device, language: String, imagesDir: URL) -> CGImage? {
    guard let caption = shot.captions[language], let fonts = fontNames[language] else { return nil }

    // 元画像: ロゴ除去 → ステータスバーを切り落とす
    let source = loadImage(imagesDir.appendingPathComponent(device.sourceDir).appendingPathComponent(shot.file))
    let cleaned = fill(removeLogos(from: source, rects: shot.logoRects), fills: shot.fills)
    let cropped = cleaned.cropped(to: CGRect(
        x: 0, y: 0,
        width: source.extent.width,
        height: source.extent.height - device.statusBarHeight
    ))
    let screen = cgImage(cropped)

    let canvas = device.canvas
    guard let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height),
        bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    // 背景
    let gradient = CGGradient(colorsSpace: sRGB, colors: [backgroundTop, backgroundBottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: 0, y: 0), options: [])

    // キャッチコピー
    let margin = canvas.width * 0.07
    let headlineHeight = drawText(
        caption.headline, fontName: fonts.headline, size: device.headlineSize,
        color: CGColor(gray: 1, alpha: 1), centerX: canvas.width / 2, top: device.captionTop,
        maxWidth: canvas.width - margin * 2, in: context, canvasHeight: canvas.height
    )
    _ = drawText(
        caption.subline, fontName: fonts.subline, size: device.sublineSize,
        color: CGColor(gray: 1, alpha: 0.85), centerX: canvas.width / 2,
        top: device.captionTop + headlineHeight + device.sublineSize * 0.5,
        maxWidth: canvas.width - margin * 2, in: context, canvasHeight: canvas.height
    )

    // 画面（角丸 + 影）
    let scale = device.screenWidth / CGFloat(screen.width)
    let screenSize = CGSize(width: device.screenWidth, height: CGFloat(screen.height) * scale)
    let screenRect = CGRect(
        x: (canvas.width - screenSize.width) / 2,
        y: canvas.height - device.screenTop - screenSize.height,
        width: screenSize.width, height: screenSize.height
    )
    let path = CGPath(roundedRect: screenRect, cornerWidth: device.cornerRadius, cornerHeight: device.cornerRadius, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 60, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(path)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.interpolationQuality = .high
    context.draw(screen, in: screenRect)
    context.restoreGState()

    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("書き出せません: \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

// MARK: - Product page header

/// プロダクトページのヘッダー（21:9, 3840x1646, 透過なし）。
/// スクリーンショットは使わず、「試合動画に中継風のスコアボードを重ねる」ことをイラストで伝える。
/// - 中央: 試合映像のフレーム（グラウンドのイラスト）
/// - 左上: 中継風スコアボード（タイマー・チームカラー・スコア）
/// - 下部: 再生バーとゴールの記録位置
/// 言語に依存しないよう文字は数字だけにし、端末ごとの切り取りに備えて主役を中央に置く。
enum HeaderArt {
    static let canvas = CGSize(width: 3840, height: 1646)
    static let home = CGColor(srgbRed: 0.17, green: 0.42, blue: 0.90, alpha: 1)
    static let away = CGColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1)
    static let white = CGColor(gray: 1, alpha: 1)

    static func render() -> CGImage? {
        guard let context = CGContext(
            data: nil, width: Int(canvas.width), height: Int(canvas.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        drawBackground(context)

        let frameSize = CGSize(width: 2080, height: 1170)
        let frame = CGRect(
            x: (canvas.width - frameSize.width) / 2,
            y: (canvas.height - frameSize.height) / 2,
            width: frameSize.width, height: frameSize.height
        )
        let framePath = CGPath(roundedRect: frame, cornerWidth: 56, cornerHeight: 56, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -30), blur: 110, color: CGColor(gray: 0, alpha: 0.5))
        context.addPath(framePath)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(framePath)
        context.clip()
        drawPitch(context, in: frame)
        drawPlayers(context, in: frame)
        drawScoreboard(context, in: frame)
        drawTimeline(context, in: frame)
        context.restoreGState()

        context.addPath(framePath)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
        context.setLineWidth(4)
        context.strokePath()

        return context.makeImage()
    }

    private static func drawBackground(_ context: CGContext) {
        let gradient = CGGradient(colorsSpace: sRGB, colors: [backgroundTop, backgroundBottom] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: .zero, options: [])

        // フレームの背後をほんのり明るくして主役を浮かせる
        let glow = CGGradient(
            colorsSpace: sRGB,
            colors: [CGColor(gray: 1, alpha: 0.16), CGColor(gray: 1, alpha: 0)] as CFArray,
            locations: [0, 1]
        )!
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 1500, options: [])
    }

    private static func drawPitch(_ context: CGContext, in frame: CGRect) {
        let horizon = frame.maxY - frame.height * 0.2

        // 観客席（奥）
        let stand = CGGradient(
            colorsSpace: sRGB,
            colors: [CGColor(srgbRed: 0.10, green: 0.15, blue: 0.13, alpha: 1),
                     CGColor(srgbRed: 0.17, green: 0.25, blue: 0.21, alpha: 1)] as CFArray,
            locations: [0, 1]
        )!
        context.saveGState()
        context.clip(to: CGRect(x: frame.minX, y: horizon, width: frame.width, height: frame.maxY - horizon))
        context.drawLinearGradient(stand, start: CGPoint(x: 0, y: frame.maxY), end: CGPoint(x: 0, y: horizon), options: [])
        // 観客（決まった並びの点。毎回同じ画像になるよう乱数は使わない）
        let crowdColors = [CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0.18), home.copy(alpha: 0.35)!, away.copy(alpha: 0.35)!]
        let spacing: CGFloat = 34
        var row = 0
        var y = horizon + 26
        while y < frame.maxY - 10 {
            var x = frame.minX + (row.isMultiple(of: 2) ? 0 : spacing / 2)
            var column = 0
            while x < frame.maxX {
                context.setFillColor(crowdColors[(column * 7 + row * 3) % crowdColors.count])
                context.fillEllipse(in: CGRect(x: x, y: y, width: 14, height: 14))
                x += spacing
                column += 1
            }
            y += spacing * 0.8
            row += 1
        }
        context.restoreGState()

        // 芝（遠近感のある縞）
        let bands = 9
        var top = horizon
        for index in 0..<bands {
            let t = pow(CGFloat(index + 1) / CGFloat(bands), 1.5)
            let bottom = horizon - (horizon - frame.minY) * t
            context.setFillColor(index.isMultiple(of: 2)
                ? CGColor(srgbRed: 0.20, green: 0.55, blue: 0.29, alpha: 1)
                : CGColor(srgbRed: 0.23, green: 0.61, blue: 0.33, alpha: 1))
            context.fill(CGRect(x: frame.minX, y: bottom, width: frame.width, height: top - bottom))
            top = bottom
        }

        // ライン
        let farY = horizon - frame.height * 0.04
        let nearY = frame.minY + frame.height * 0.06
        let farInset = frame.width * 0.14
        let nearInset = -frame.width * 0.1
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
        context.setLineWidth(7)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: frame.minX + nearInset, y: nearY))
        context.addLine(to: CGPoint(x: frame.minX + farInset, y: farY))
        context.addLine(to: CGPoint(x: frame.maxX - farInset, y: farY))
        context.addLine(to: CGPoint(x: frame.maxX - nearInset, y: nearY))
        context.move(to: CGPoint(x: frame.midX, y: farY))
        context.addLine(to: CGPoint(x: frame.midX, y: nearY))
        context.strokePath()

        let circleCenterY = farY - (farY - nearY) * 0.45
        context.strokeEllipse(in: CGRect(
            x: frame.midX - frame.width * 0.13, y: circleCenterY - frame.height * 0.11,
            width: frame.width * 0.26, height: frame.height * 0.22
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 0.85))
        context.fillEllipse(in: CGRect(x: frame.midX - 9, y: circleCenterY - 6, width: 18, height: 12))
    }

    private static func drawPlayers(_ context: CGContext, in frame: CGRect) {
        // (x, y) はフレーム内の相対位置（0〜1、左下原点）。y が小さいほど手前で大きく描く
        let players: [(CGFloat, CGFloat, CGColor)] = [
            (0.22, 0.58, home), (0.36, 0.42, home), (0.47, 0.64, home), (0.61, 0.30, home),
            (0.30, 0.66, away), (0.55, 0.52, away), (0.70, 0.62, away), (0.80, 0.40, away),
        ]
        for (x, y, color) in players {
            drawPlayer(context, at: CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y),
                       scale: 1.35 - y * 0.75, color: color)
        }
        // ボール
        let ball = CGPoint(x: frame.minX + frame.width * 0.585, y: frame.minY + frame.height * 0.33)
        context.setFillColor(CGColor(gray: 0, alpha: 0.25))
        context.fillEllipse(in: CGRect(x: ball.x - 16, y: ball.y - 8, width: 36, height: 12))
        context.setFillColor(white)
        context.fillEllipse(in: CGRect(x: ball.x - 14, y: ball.y, width: 28, height: 28))
    }

    private static func drawPlayer(_ context: CGContext, at point: CGPoint, scale: CGFloat, color: CGColor) {
        let bodyWidth = 34 * scale
        let bodyHeight = 78 * scale
        let head = 30 * scale
        context.setFillColor(CGColor(gray: 0, alpha: 0.22))
        context.fillEllipse(in: CGRect(x: point.x - bodyWidth, y: point.y - 8 * scale, width: bodyWidth * 2, height: 16 * scale))
        context.setFillColor(color)
        context.addPath(CGPath(
            roundedRect: CGRect(x: point.x - bodyWidth / 2, y: point.y, width: bodyWidth, height: bodyHeight),
            cornerWidth: bodyWidth / 2, cornerHeight: bodyWidth / 2, transform: nil
        ))
        context.fillPath()
        context.setFillColor(CGColor(srgbRed: 0.96, green: 0.84, blue: 0.72, alpha: 1))
        context.fillEllipse(in: CGRect(x: point.x - head / 2, y: point.y + bodyHeight + 4 * scale, width: head, height: head))
    }

    /// アプリの Dark テーマのスコアボードを模した中継風の表示
    private static func drawScoreboard(_ context: CGContext, in frame: CGRect) {
        let height: CGFloat = 150
        let origin = CGPoint(x: frame.minX + 64, y: frame.maxY - 56 - height)
        let timerWidth: CGFloat = 300
        let barWidth: CGFloat = 640

        // 本体（暗い帯）
        let bar = CGRect(x: origin.x, y: origin.y, width: timerWidth + barWidth, height: height)
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: CGColor(gray: 0, alpha: 0.4))
        context.addPath(CGPath(roundedRect: bar, cornerWidth: 22, cornerHeight: 22, transform: nil))
        context.setFillColor(CGColor(srgbRed: 0.08, green: 0.11, blue: 0.16, alpha: 0.92))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        // タイマー（白地）
        let timer = CGRect(x: origin.x, y: origin.y, width: timerWidth, height: height)
        let timerPath = CGMutablePath()
        timerPath.addRoundedRect(in: timer, cornerWidth: 22, cornerHeight: 22)
        context.saveGState()
        context.clip(to: CGRect(x: timer.minX, y: timer.minY, width: timer.width, height: timer.height))
        context.addPath(timerPath)
        context.addRect(CGRect(x: timer.maxX - 30, y: timer.minY, width: 30, height: timer.height))
        context.setFillColor(white)
        context.fillPath()
        context.restoreGState()
        drawNumber("45:00", size: 80, color: CGColor(srgbRed: 0.08, green: 0.11, blue: 0.16, alpha: 1),
                   center: CGPoint(x: timer.midX, y: timer.midY), in: context)

        // チームカラー + スコア
        let midY = origin.y + height / 2
        let swatchSize = CGSize(width: 120, height: 26)
        let homeX = timer.maxX + 46
        context.addPath(CGPath(roundedRect: CGRect(x: homeX, y: midY - swatchSize.height / 2, width: swatchSize.width, height: swatchSize.height),
                               cornerWidth: 11, cornerHeight: 11, transform: nil))
        context.setFillColor(home)
        context.fillPath()

        let scoreRadius: CGFloat = 50
        let homeScoreCenter = CGPoint(x: homeX + swatchSize.width + 36 + scoreRadius, y: midY)
        let awayScoreCenter = CGPoint(x: homeScoreCenter.x + scoreRadius * 2 + 24, y: midY)
        for (center, score) in [(homeScoreCenter, "2"), (awayScoreCenter, "1")] {
            context.setFillColor(white)
            context.fillEllipse(in: CGRect(x: center.x - scoreRadius, y: center.y - scoreRadius, width: scoreRadius * 2, height: scoreRadius * 2))
            drawNumber(score, size: 72, color: CGColor(srgbRed: 0.08, green: 0.11, blue: 0.16, alpha: 1), center: center, in: context)
        }

        context.addPath(CGPath(roundedRect: CGRect(x: awayScoreCenter.x + scoreRadius + 36, y: midY - swatchSize.height / 2,
                                                   width: swatchSize.width, height: swatchSize.height),
                               cornerWidth: 11, cornerHeight: 11, transform: nil))
        context.setFillColor(away)
        context.fillPath()
    }

    /// 再生バーと、ゴールを記録した位置
    private static func drawTimeline(_ context: CGContext, in frame: CGRect) {
        // 下部を暗くしてバーを見やすくする
        let shade = CGGradient(
            colorsSpace: sRGB,
            colors: [CGColor(gray: 0, alpha: 0.5), CGColor(gray: 0, alpha: 0)] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(shade, start: CGPoint(x: 0, y: frame.minY),
                                   end: CGPoint(x: 0, y: frame.minY + frame.height * 0.28), options: [])

        let track = CGRect(x: frame.minX + 110, y: frame.minY + 86, width: frame.width - 220, height: 14)
        let progress: CGFloat = 0.64
        context.addPath(CGPath(roundedRect: track, cornerWidth: 7, cornerHeight: 7, transform: nil))
        context.setFillColor(CGColor(gray: 1, alpha: 0.35))
        context.fillPath()
        context.addPath(CGPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: track.width * progress, height: track.height),
                               cornerWidth: 7, cornerHeight: 7, transform: nil))
        context.setFillColor(CGColor(srgbRed: 0.30, green: 0.80, blue: 0.49, alpha: 1))
        context.fillPath()

        // スコア 2-1 に合わせたゴールの印
        for (position, color) in [(0.18, home), (0.41, away), (0.57, home)] as [(CGFloat, CGColor)] {
            let center = CGPoint(x: track.minX + track.width * position, y: track.maxY + 52)
            context.setFillColor(white)
            context.fillEllipse(in: CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52))
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: center.x - 19, y: center.y - 19, width: 38, height: 38))
            context.setFillColor(white)
            context.fill(CGRect(x: center.x - 3, y: track.maxY + 4, width: 6, height: 22))
        }

        let knob = CGPoint(x: track.minX + track.width * progress, y: track.midY)
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: CGColor(gray: 0, alpha: 0.4))
        context.setFillColor(white)
        context.fillEllipse(in: CGRect(x: knob.x - 30, y: knob.y - 30, width: 60, height: 60))
        context.setShadow(offset: .zero, blur: 0, color: nil)
    }

    private static func drawNumber(_ text: String, size: CGFloat, color: CGColor, center: CGPoint, in context: CGContext) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .heavy) as CTFont
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        // ImageBounds は現在の textPosition を基準に返るので、原点で測る
        context.textPosition = .zero
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX, y: center.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, context)
    }
}

// MARK: - 実行

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let imagesDir = root.appendingPathComponent("AppStore/images")
let outputDir = root.appendingPathComponent("AppStore/screenshots")
let languages = CommandLine.arguments.count > 1 ? Array(CommandLine.arguments.dropFirst()) : ["ja"]

for language in languages {
    for device in devices {
        for (index, shot) in device.shots.enumerated() {
            guard let image = render(shot: shot, device: device, language: language, imagesDir: imagesDir) else {
                print("スキップ: \(language) \(device.name) \(shot.file)（キャプションまたはフォント未設定）")
                continue
            }
            let url = outputDir
                .appendingPathComponent(language)
                .appendingPathComponent(device.name)
                .appendingPathComponent(String(format: "%02d.png", index + 1))
            writePNG(image, to: url)
            print("\(url.path(percentEncoded: false)) (\(image.width)x\(image.height))")
        }
    }
}

// ヘッダーは言語に依存しないので1枚だけ作る
if let header = HeaderArt.render() {
    let url = outputDir.appendingPathComponent("header/header_21x9.png")
    writePNG(header, to: url)
    print("\(url.path(percentEncoded: false)) (\(header.width)x\(header.height))")
}

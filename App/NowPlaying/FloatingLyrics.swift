import AVFoundation
import AVKit
import CoreMedia
import Observation
import UIKit

/// Finestra flottante con il testo (Picture in Picture), come quella di Dynamic Lyrics.
///
/// iOS permette di tenere sopra tutte le app solo una finestra "video". Quindi disegniamo il testo
/// come se fosse un video: a ogni cambio di riga creiamo un fotogramma e lo mandiamo a un
/// `AVSampleBufferDisplayLayer`, che il sistema mostra nella finestra Picture in Picture.
/// La finestra scorre sempre in tempo reale, anche dentro altre app, perché la disegna l'iPhone stesso.
@MainActor
@Observable
final class FloatingLyricsController: NSObject {
    /// La finestra flottante è aperta.
    private(set) var isActive = false
    /// iOS è pronto ad aprirla (serve almeno un fotogramma e la sessione audio attiva).
    private(set) var isPossible = false

    /// Apri la finestra da sola quando esci da Lyrics.
    var opensAutomatically: Bool {
        didSet {
            UserDefaults.standard.set(opensAutomatically, forKey: Self.autoKey)
            pipController?.canStartPictureInPictureAutomaticallyFromInline = opensAutomatically
        }
    }

    /// Cosa scrivere nella finestra: lo fornisce il modello (stessi testi della Modalità auto).
    @ObservationIgnored var textsProvider: @MainActor (Date) -> CarModeTexts = { _ in
        CarModeTexts(title: "Lyrics", current: "Niente in riproduzione", next: "")
    }

    @ObservationIgnored let hostView = FloatingLyricsHostView()
    @ObservationIgnored private var pipController: AVPictureInPictureController?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var lastTexts: CarModeTexts?
    @ObservationIgnored private var lastFrame = Date.distantPast
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?

    private static let autoKey = "floatingAutoStart"
    static let frameSize = CGSize(width: 960, height: 540)

    override init() {
        opensAutomatically = UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true
        super.init()
    }

    /// Prepara la finestra (da chiamare con l'app aperta). Non la apre ancora.
    func prepare() {
        guard pipController == nil, AVPictureInPictureController.isPictureInPictureSupported() else {
            startRendering()
            return
        }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: hostView.displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = opensAutomatically
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.isPossible = possible }
        }
        pipController = controller
        startRendering()
    }

    func toggle() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }

    // MARK: - Disegno

    private func startRendering() {
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.renderIfNeeded(now: Date())
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func renderIfNeeded(now: Date) {
        let texts = textsProvider(now)
        // Nuovo fotogramma quando cambia il testo, e comunque ogni 2 secondi (la finestra resta "viva").
        guard texts != lastTexts || now.timeIntervalSince(lastFrame) > 2 else { return }
        lastTexts = texts
        lastFrame = now
        guard let sample = Self.makeSampleBuffer(texts: texts) else { return }
        let renderer = hostView.displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
    }

    /// Crea un fotogramma 16:9 con titolo, riga in corso (grande) e riga successiva.
    nonisolated static func makeSampleBuffer(texts: CarModeTexts) -> CMSampleBuffer? {
        let width = Int(frameSize.width), height = Int(frameSize.height)
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer
        else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Coordinate "UIKit" (origine in alto a sinistra).
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        drawFrame(texts: texts, size: frameSize)
        UIGraphicsPopContext()

        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                 formatDescription: format, sampleTiming: &timing,
                                                 sampleBufferOut: &sample)
        guard let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    /// Disegna il contenuto di un fotogramma (usato anche dalle anteprime).
    nonisolated static func drawFrame(texts: CarModeTexts, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        UIColor(red: 0.07, green: 0.06, blue: 0.14, alpha: 1).setFill()
        UIRectFill(bounds)

        let margin: CGFloat = 44
        let accent = UIColor(red: 1.0, green: 0.69, blue: 0.38, alpha: 1)
        let titleFont = roundedFont(size: 30, weight: .semibold)
        let title = NSAttributedString(string: (texts.isPaused ? "⏸ " : "♪ ") + texts.title, attributes: [
            .font: titleFont, .foregroundColor: accent,
        ])
        title.draw(with: CGRect(x: margin, y: 30, width: size.width - margin * 2, height: 44),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)

        // Riga successiva in basso, poi la riga corrente grande nello spazio che resta.
        var bottom = size.height - 34
        if !texts.next.isEmpty {
            let next = NSAttributedString(string: texts.next, attributes: [
                .font: roundedFont(size: 34, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.45),
            ])
            let nextRect = CGRect(x: margin, y: bottom - 46, width: size.width - margin * 2, height: 46)
            next.draw(with: nextRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            bottom = nextRect.minY - 14
        }

        let area = CGRect(x: margin, y: 90, width: size.width - margin * 2, height: bottom - 90)
        var fontSize: CGFloat = 76
        var current = NSAttributedString()
        var needed = CGRect.zero
        repeat {
            current = NSAttributedString(string: texts.current, attributes: [
                .font: roundedFont(size: fontSize, weight: .heavy), .foregroundColor: UIColor.white,
            ])
            needed = current.boundingRect(with: CGSize(width: area.width, height: .greatestFiniteMagnitude),
                                          options: .usesLineFragmentOrigin, context: nil)
            fontSize -= 4
        } while needed.height > area.height && fontSize > 26
        let y = area.minY + max(0, (area.height - needed.height) / 2)
        current.draw(with: CGRect(x: area.minX, y: y, width: area.width, height: area.height),
                     options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    nonisolated private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

// MARK: - Delegati Picture in Picture

extension FloatingLyricsController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = false }
    }
}

extension FloatingLyricsController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        // Contenuto "in diretta": nessuna barra di avanzamento.
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

/// Vista che contiene il "video" del testo. Deve stare nella finestra dell'app perché iOS permetta
/// la finestra flottante; la mostriamo piccolissima e quasi trasparente.
final class FloatingLyricsHostView: UIView {
    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        displayLayer.videoGravity = .resizeAspect
        layer.addSublayer(displayLayer)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = bounds
    }
}

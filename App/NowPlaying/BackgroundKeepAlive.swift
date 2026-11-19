import AVFoundation
import Foundation

/// Mantiene Lyrics attiva quando l'iPhone è bloccato o l'app è in background, così la Live Activity
/// (schermata di blocco e CarPlay) continua a seguire il testo.
///
/// Come funziona: riproduce in loop un buffer di silenzio con una sessione audio "mixWithOthers",
/// che si somma a Spotify senza interromperlo né sostituirlo nei controlli "In riproduzione".
/// Richiede `UIBackgroundModes = audio` in Info.plist.
/// Nota: è adatto a un'app personale; l'App Store non accetterebbe questo uso dell'audio in background.
@MainActor
final class BackgroundKeepAlive {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var wantsToRun = false
    private var interruptionObserver: NSObjectProtocol?

    var isRunning: Bool { engine?.isRunning == true }

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let ended = rawType == AVAudioSession.InterruptionType.ended.rawValue
            MainActor.assumeIsolated {
                guard let self, ended, self.wantsToRun else { return }
                // Dopo una telefonata o Siri, riparte.
                self.teardown()
                self.start()
            }
        }
    }

    func start() {
        wantsToRun = true
        guard !isRunning else { return }
        teardown()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            let format = engine.mainMixerNode.outputFormat(forBus: 0)
            engine.connect(player, to: engine.mainMixerNode, format: format)

            guard format.sampleRate > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate))
            else { return }
            buffer.frameLength = buffer.frameCapacity
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    channels[channel].update(repeating: 0, count: Int(buffer.frameLength))
                }
            }

            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            self.engine = engine
            self.player = player
        } catch {
            teardown()
        }
    }

    func stop() {
        wantsToRun = false
        teardown()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func teardown() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }
}

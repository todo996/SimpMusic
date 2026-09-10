import AVFoundation
import Combine
import Foundation
import MediaPlayer

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var currentTrack: MusicTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init() {
        configureAudioSession()
        configureRemoteCommands()
    }

    func play(track: MusicTrack, streamURL: URL) {
        configureAudioSession()
        let item = AVPlayerItem(url: streamURL)
        player?.pause()
        player = AVPlayer(playerItem: item)
        currentTrack = track
        progress = 0
        duration = 0
        isPlaying = true
        installObservers(for: item)
        updateNowPlaying()
        player?.play()
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func seek(to value: Double) {
        guard duration > 0 else { return }
        let seconds = value * duration
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        progress = value
        updateNowPlaying()
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default, options: [.allowAirPlay])
        try? audioSession.setActive(true)
    }

    private func installObservers(for item: AVPlayerItem) {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let current = time.seconds
            let total = item.duration.seconds
            guard current.isFinite, total.isFinite, total > 0 else { return }
            self.progress = min(max(current / total, 0), 1)
            self.duration = total
            self.updateNowPlaying()
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.progress = 1
                self?.updateNowPlaying()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPlaying else { return }
                self.togglePlayback()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.togglePlayback()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artist,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress * duration
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

import AVFoundation
import MediaPlayer

@MainActor
final class PlayerController: NSObject, ObservableObject {
    @Published private(set) var currentTrack: MusicTrack?
    @Published private(set) var queue: [MusicTrack] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var errorMessage: String?

    private let player = AVPlayer()
    private var observer: Any?
    private var endObserver: NSObjectProtocol?
    private var queueIndex = 0

    override init() {
        super.init()
        configureAudioSession()
        configureRemoteCommands()
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let current = max(0, time.seconds.isFinite ? time.seconds : 0)
            let total = self.player.currentItem?.duration.seconds ?? 0
            self.elapsed = current
            self.duration = total.isFinite ? max(0, total) : 0
            self.progress = self.duration > 0 ? min(1, current / self.duration) : 0
            self.updateNowPlayingInfo()
        }
    }

    deinit {
        if let observer { player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func play(track: MusicTrack, streamURL: URL) {
        if let index = queue.firstIndex(of: track) {
            queueIndex = index
        } else {
            queue = [track]
            queueIndex = 0
        }
        currentTrack = track
        let item = AVPlayerItem(url: streamURL)
        player.replaceCurrentItem(with: item)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.next()
        }
        updateNowPlayingInfo()
        player.play()
        isPlaying = true
    }

    func setQueue(_ tracks: [MusicTrack], startAt index: Int = 0) {
        queue = tracks
        queueIndex = min(max(0, index), max(0, tracks.count - 1))
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else if currentTrack != nil {
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func seek(to progress: Double) {
        guard duration > 0 else { return }
        let target = min(1, max(0, progress)) * duration
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func next() {
        guard !queue.isEmpty else { return }
        let nextIndex = queueIndex + 1
        guard nextIndex < queue.count else {
            player.pause()
            isPlaying = false
            return
        }
        queueIndex = nextIndex
        NotificationCenter.default.post(
            name: .simpMusicRequestStream,
            object: queue[nextIndex]
        )
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if elapsed > 5 {
            seek(to: 0)
            return
        }
        let previousIndex = queueIndex - 1
        guard previousIndex >= 0 else { return }
        queueIndex = previousIndex
        NotificationCenter.default.post(
            name: .simpMusicRequestStream,
            object: queue[previousIndex]
        )
    }

    private func configureAudioSession() {
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default, options: [])
            try audio.setActive(true)
        } catch {
            errorMessage = "Không thể bật phát nền: \(error.localizedDescription)"
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.togglePlayback()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayback()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: (self?.duration ?? 0) > 0 ? event.positionTime / (self?.duration ?? 1) : 0)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension Notification.Name {
    static let simpMusicRequestStream = Notification.Name("SimpMusicRequestStream")
}

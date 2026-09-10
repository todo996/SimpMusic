import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var source: MusicSource = .all
    @Published var query = ""
    @Published private(set) var homeTracks: [MusicTrack] = []
    @Published private(set) var tracks: [MusicTrack] = []
    @Published private(set) var favorites: [MusicTrack] = []
    @Published private(set) var history: [MusicTrack] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingHome = false
    @Published private(set) var isResolvingTrackID: String?
    @Published var errorMessage: String?
    @Published private(set) var lyrics: LyricsResult?
    @Published private(set) var isLoadingLyrics = false
    @Published var darkMode: Bool

    let player: PlayerController

    private let youtube = YouTubeClient()
    private let soundCloud = SoundCloudClient()
    private let lyricsClient = LyricsClient()
    private var streamRequestObserver: NSObjectProtocol?

    private let favoritesKey = "simpmusic.ios.full.favorites"
    private let historyKey = "simpmusic.ios.full.history"
    private let darkModeKey = "simpmusic.ios.full.dark_mode"

    init(player: PlayerController = PlayerController()) {
        self.player = player
        self.darkMode = UserDefaults.standard.object(forKey: darkModeKey) as? Bool ?? true
        loadLocalData()
        streamRequestObserver = NotificationCenter.default.addObserver(
            forName: .simpMusicRequestStream,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let track = notification.object as? MusicTrack else { return }
            Task { @MainActor [weak self] in
                await self?.play(track)
            }
        }
        Task { @MainActor [weak self] in
            await self?.loadHome()
        }
    }

    deinit {
        if let streamRequestObserver { NotificationCenter.default.removeObserver(streamRequestObserver) }
    }

    var filteredTracks: [MusicTrack] {
        switch source {
        case .all: return tracks
        case .youtube: return tracks.filter { $0.source == .youtube }
        case .soundCloud: return tracks.filter { $0.source == .soundCloud }
        }
    }

    func loadHome() async {
        guard !isLoadingHome else { return }
        isLoadingHome = true
        do {
            homeTracks = try await youtube.home()
        } catch {
            if homeTracks.isEmpty { errorMessage = error.localizedDescription }
        }
        isLoadingHome = false
    }

    func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !isSearching else { return }
        isSearching = true
        tracks = []
        Task { @MainActor [weak self] in
            guard let self else { return }
            let youtube = self.youtube
            let soundCloud = self.soundCloud
            let results = await withTaskGroup(of: [MusicTrack].self, returning: [[MusicTrack]].self) { group in
                group.addTask { (try? await youtube.search(term)) ?? [] }
                group.addTask { (try? await soundCloud.search(term)) ?? [] }
                var collected: [[MusicTrack]] = []
                for await result in group { collected.append(result) }
                return collected
            }
            let merged = results.flatMap { $0 }
            if merged.isEmpty {
                errorMessage = "Không có kết quả hoặc nguồn nhạc tạm thời không phản hồi."
            }
            tracks = merged
            isSearching = false
        }
    }

    func playFromHome(_ track: MusicTrack) {
        player.setQueue(homeTracks)
        Task { @MainActor [weak self] in await self?.play(track) }
    }

    func playFromSearch(_ track: MusicTrack) {
        player.setQueue(filteredTracks)
        Task { @MainActor [weak self] in await self?.play(track) }
    }

    func play(_ track: MusicTrack) async {
        isResolvingTrackID = track.id
        do {
            let url: URL
            switch track.source {
            case .youtube:
                url = try await youtube.resolveStream(for: track)
            case .soundCloud:
                url = try await soundCloud.resolveStream(for: track)
            case .all:
                throw MusicError.streamUnavailable("nguồn nhạc")
            }
            player.play(track: track, streamURL: url)
            history.removeAll { $0.id == track.id }
            history.insert(track, at: 0)
            history = Array(history.prefix(100))
            save(history, key: historyKey)
            await loadLyrics(for: track)
        } catch {
            errorMessage = error.localizedDescription
        }
        isResolvingTrackID = nil
    }

    func toggleFavorite(_ track: MusicTrack) {
        if favorites.contains(track) {
            favorites.removeAll { $0.id == track.id }
        } else {
            favorites.insert(track, at: 0)
        }
        save(favorites, key: favoritesKey)
    }

    func isFavorite(_ track: MusicTrack) -> Bool {
        favorites.contains(track)
    }

    func loadLyrics(for track: MusicTrack) async {
        isLoadingLyrics = true
        lyrics = await lyricsClient.lyrics(for: track)
        isLoadingLyrics = false
    }

    func clearHistory() {
        history = []
        save(history, key: historyKey)
    }

    func setDarkMode(_ enabled: Bool) {
        darkMode = enabled
        UserDefaults.standard.set(enabled, forKey: darkModeKey)
    }

    func refreshAll() {
        Task { @MainActor [weak self] in
            await self?.loadHome()
        }
    }

    private func loadLocalData() {
        favorites = load(key: favoritesKey)
        history = load(key: historyKey)
    }

    private func load<T: Decodable>(key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([T].self, from: data) else { return [] }
        return value
    }

    private func save<T: Encodable>(_ value: [T], key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

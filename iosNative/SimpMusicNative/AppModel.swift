import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var query = ""
    @Published var source: MusicSource = .all
    @Published private(set) var tracks: [MusicTrack] = []
    @Published private(set) var isSearching = false
    @Published private(set) var resolvingTrackID: String?
    @Published var errorMessage: String?
    @Published private(set) var player: PlayerController

    private let soundCloud = SoundCloudClient()
    private let youtube = YouTubeClient()
    private var searchTask: Task<Void, Never>?

    init() {
        player = PlayerController()
    }

    deinit {
        searchTask?.cancel()
    }

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        isSearching = true
        errorMessage = nil

        let selectedSource = source
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var found: [MusicTrack] = []
            var errors: [Error] = []

            if selectedSource == .all || selectedSource == .soundCloud {
                do {
                    found.append(contentsOf: try await soundCloud.search(trimmed))
                } catch {
                    errors.append(error)
                }
            }
            if selectedSource == .all || selectedSource == .youtube {
                do {
                    found.append(contentsOf: try await youtube.search(trimmed))
                } catch {
                    errors.append(error)
                }
            }

            guard !Task.isCancelled else { return }
            tracks = found
            isSearching = false
            if found.isEmpty {
                errorMessage = errors.first?.localizedDescription ?? MusicError.noResults.localizedDescription
            } else if found.count < 2, let firstError = errors.first {
                errorMessage = "Một nguồn không phản hồi: \(firstError.localizedDescription)"
            }
        }
    }

    func play(_ track: MusicTrack) {
        resolvingTrackID = track.id
        errorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let streamURL: URL
                switch track.source {
                case .soundCloud:
                    streamURL = try await soundCloud.resolveStream(for: track)
                case .youtube:
                    streamURL = try await youtube.resolveStream(for: track)
                case .all:
                    throw MusicError.streamUnavailable("Nguồn nhạc")
                }
                player.play(track: track, streamURL: streamURL)
            } catch {
                errorMessage = error.localizedDescription
            }
            resolvingTrackID = nil
        }
    }
}

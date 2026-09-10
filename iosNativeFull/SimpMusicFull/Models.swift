import Foundation

enum MusicSource: String, CaseIterable, Codable, Identifiable {
    case all = "Tất cả"
    case youtube = "YouTube Music"
    case soundCloud = "SoundCloud"

    var id: String { rawValue }
}

struct MusicTrack: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let source: MusicSource
    let artworkURL: URL?
    let permalinkURL: URL?
    let duration: TimeInterval?

    var durationText: String {
        guard let duration else { return "" }
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct LyricsLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval?
    let text: String
}

struct LyricsResult: Equatable {
    let trackName: String
    let artistName: String
    let lines: [LyricsLine]
    let synced: Bool
}

enum AppTab: Hashable {
    case home, search, library, settings
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case favorites = "Yêu thích"
    case history = "Lịch sử"
    case playlists = "Playlist"

    var id: String { rawValue }
}

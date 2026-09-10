import Foundation

enum MusicSource: String, CaseIterable, Identifiable {
    case all
    case soundCloud = "SoundCloud"
    case youtube = "YouTube"

    var id: String { rawValue }
}

struct MusicTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let source: MusicSource
    let artworkURL: URL?
    let permalinkURL: URL?
    let duration: TimeInterval?
}

enum MusicError: LocalizedError {
    case invalidResponse
    case providerUnavailable(String)
    case streamUnavailable(String)
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Máy chủ trả về dữ liệu không hợp lệ."
        case .providerUnavailable(let provider):
            return "Không kết nối được với \(provider). Hãy thử lại sau."
        case .streamUnavailable(let provider):
            return "\(provider) không cung cấp luồng phát trực tiếp cho bài này."
        case .noResults:
            return "Không tìm thấy bài hát phù hợp."
        }
    }
}

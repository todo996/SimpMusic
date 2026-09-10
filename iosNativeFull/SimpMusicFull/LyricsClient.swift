import Foundation

actor LyricsClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lyrics(for track: MusicTrack) async -> LyricsResult? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album ?? ""),
            URLQueryItem(name: "duration", value: track.duration.map { String(Int($0)) } ?? "")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("SimpMusic-iOS/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let plain = object["plainLyrics"] as? String
        let synced = object["syncedLyrics"] as? String
        let source = synced ?? plain
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let lines = source.components(separatedBy: .newlines).compactMap { line -> LyricsLine? in
            if let match = line.range(of: #"^\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]\s*(.*)$"#, options: .regularExpression) {
                let text = String(line[match])
                let parts = text.replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: " ")
                    .split(separator: " ", maxSplits: 1)
                let timestamp = parts.first?.split(separator: ":").compactMap { Double($0) }
                let seconds = timestamp.map { ($0.first ?? 0) * 60 + ($0.dropFirst().first ?? 0) }
                return LyricsLine(time: seconds, text: parts.dropFirst().joined(separator: " "))
            }
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : LyricsLine(time: nil, text: text)
        }
        return LyricsResult(
            trackName: object["trackName"] as? String ?? track.title,
            artistName: object["artistName"] as? String ?? track.artist,
            lines: lines,
            synced: synced != nil
        )
    }
}

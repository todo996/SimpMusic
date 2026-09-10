import Foundation

actor YouTubeClient {
    private let session: URLSession
    private let clientName = "WEB_REMIX"
    private let clientVersion = "1.20260304.03.00"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ query: String) async throws -> [MusicTrack] {
        let object = try await post(endpoint: "search", body: [
            "context": ["client": [
                "clientName": clientName,
                "clientVersion": clientVersion,
                "hl": "en",
                "gl": "US"
            ]],
            "query": query
        ])

        var tracks: [MusicTrack] = []
        walk(object) { dictionary in
            guard let videoID = dictionary["videoId"] as? String,
                  let title = firstText(dictionary["title"]) else { return false }
            let artist = firstText(dictionary["ownerText"])
                ?? firstText(dictionary["longBylineText"])
                ?? "YouTube"
            let thumbnail = firstThumbnail(dictionary["thumbnail"])
            tracks.append(MusicTrack(
                id: videoID,
                title: title,
                artist: artist,
                source: .youtube,
                artworkURL: thumbnail,
                permalinkURL: URL(string: "https://music.youtube.com/watch?v=\(videoID)"),
                duration: nil
            ))
            return tracks.count >= 25
        }
        return tracks
    }

    func resolveStream(for track: MusicTrack) async throws -> URL {
        let object = try await post(endpoint: "player", body: [
            "context": ["client": [
                "clientName": clientName,
                "clientVersion": clientVersion,
                "hl": "en",
                "gl": "US"
            ]],
            "videoId": track.id
        ])

        var candidates: [(URL, Int)] = []
        collectDictionaries(object).forEach { dictionary in
            guard let mimeType = dictionary["mimeType"] as? String,
                  mimeType.hasPrefix("audio/") else { return }
            if let rawURL = dictionary["url"] as? String,
               let url = URL(string: rawURL) {
                candidates.append((url, dictionary["bitrate"] as? Int ?? 0))
            }
        }
        if let best = candidates.max(by: { $0.1 < $1.1 })?.0 {
            return best
        }
        throw MusicError.streamUnavailable("YouTube")
    }

    private func post(endpoint: String, body: [String: Any]) async throws -> Any {
        var components = URLComponents(string: "https://music.youtube.com/youtubei/v1/\(endpoint)")!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MusicError.providerUnavailable("YouTube")
            }
            return try JSONSerialization.jsonObject(with: data)
        } catch let error as MusicError {
            throw error
        } catch {
            throw MusicError.providerUnavailable("YouTube")
        }
    }

    private func walk(_ value: Any, visit: ([String: Any]) -> Bool) {
        if let dictionary = value as? [String: Any] {
            if visit(dictionary) { return }
            for child in dictionary.values where !walkChild(child, visit: visit) { }
        } else if let array = value as? [Any] {
            for child in array where !walkChild(child, visit: visit) { }
        }
    }

    private func walkChild(_ value: Any, visit: ([String: Any]) -> Bool) -> Bool {
        if let dictionary = value as? [String: Any] {
            if visit(dictionary) { return true }
            for child in dictionary.values where walkChild(child, visit: visit) { return true }
        } else if let array = value as? [Any] {
            for child in array where walkChild(child, visit: visit) { return true }
        }
        return false
    }

    private func collectDictionaries(_ value: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []
        walk(value) { dictionary in
            result.append(dictionary)
            return false
        }
        return result
    }

    private func firstText(_ value: Any?) -> String? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let simpleText = dictionary["simpleText"] as? String { return simpleText }
        if let runs = dictionary["runs"] as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private func firstThumbnail(_ value: Any?) -> URL? {
        guard let dictionary = value as? [String: Any],
              let thumbnails = dictionary["thumbnails"] as? [[String: Any]] else { return nil }
        return thumbnails.reversed().compactMap { thumbnail in
            guard let value = thumbnail["url"] as? String else { return nil }
            return URL(string: value)
        }.first
    }
}

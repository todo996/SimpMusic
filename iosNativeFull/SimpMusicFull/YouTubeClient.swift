import Foundation

actor YouTubeClient {
    private let session: URLSession
    private let searchClient = (name: "WEB_REMIX", version: "1.20260304.03.00")
    private let playbackClients = [
        (name: "ANDROID_VR", version: "1.60.19"),
        (name: "WEB_EMBEDDED_PLAYER", version: "1.20240709.01.00"),
        (name: "WEB_REMIX", version: "1.20260304.03.00")
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ query: String) async throws -> [MusicTrack] {
        let object = try await post(endpoint: "search", client: searchClient, body: [
            "context": ["client": [
                "clientName": searchClient.name,
                "clientVersion": searchClient.version,
                "hl": "vi",
                "gl": "VN"
            ]],
            "query": query,
            "params": "EgWKAQIIAWoKEAkQBRAEEAoQBQ%3D%3D"
        ])

        var tracks: [MusicTrack] = []
        walk(object) { dictionary in
            guard tracks.count < 40,
                  let videoID = dictionary["videoId"] as? String,
                  let title = firstText(dictionary["title"]),
                  !title.isEmpty else { return false }
            let artist = firstText(dictionary["ownerText"])
                ?? firstText(dictionary["longBylineText"])
                ?? firstText(dictionary["shortBylineText"])
                ?? "YouTube"
            tracks.append(MusicTrack(
                id: videoID,
                title: title,
                artist: artist,
                album: firstText(dictionary["album"]),
                source: .youtube,
                artworkURL: firstThumbnail(dictionary["thumbnail"]),
                permalinkURL: URL(string: "https://music.youtube.com/watch?v=\(videoID)"),
                duration: duration(from: dictionary)
            ))
            return false
        }
        return deduplicate(tracks)
    }

    /// The Android app starts from YouTube Music Home. iOS uses the same public browse endpoint
    /// and turns its renderer tree into the same track cards, while ignoring unsupported cards.
    func home() async throws -> [MusicTrack] {
        let object = try await post(endpoint: "browse", client: searchClient, body: [
            "context": ["client": [
                "clientName": searchClient.name,
                "clientVersion": searchClient.version,
                "hl": "vi",
                "gl": "VN"
            ]],
            "browseId": "FEmusic_home"
        ])
        var tracks: [MusicTrack] = []
        walk(object) { dictionary in
            guard tracks.count < 60,
                  let videoID = dictionary["videoId"] as? String,
                  let title = firstText(dictionary["title"]),
                  !title.isEmpty else { return false }
            let artist = firstText(dictionary["subtitle"])
                ?? firstText(dictionary["longBylineText"])
                ?? "YouTube Music"
            tracks.append(MusicTrack(
                id: videoID,
                title: title,
                artist: artist,
                album: nil,
                source: .youtube,
                artworkURL: firstThumbnail(dictionary["thumbnail"]),
                permalinkURL: URL(string: "https://music.youtube.com/watch?v=\(videoID)"),
                duration: duration(from: dictionary)
            ))
            return false
        }
        return deduplicate(tracks)
    }

    func resolveStream(for track: MusicTrack) async throws -> URL {
        var lastError: Error = MusicError.streamUnavailable("YouTube Music")
        for client in playbackClients {
            do {
                let object = try await post(endpoint: "player", client: client, body: [
                    "context": ["client": [
                        "clientName": client.name,
                        "clientVersion": client.version,
                        "hl": "vi",
                        "gl": "VN"
                    ]],
                    "videoId": track.id
                ])
                if let url = bestAudioURL(in: object) {
                    return url
                }
                if let manifest = findString(in: object, key: "hlsManifestUrl"),
                   let url = URL(string: manifest) {
                    return url
                }
                if let reason = playabilityReason(in: object) {
                    lastError = MusicError.providerMessage("YouTube: \(reason)")
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func post(endpoint: String, client: (name: String, version: String), body: [String: Any]) async throws -> Any {
        var components = URLComponents(string: "https://music.youtube.com/youtubei/v1/\(endpoint)")!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("SimpMusic-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MusicError.providerUnavailable("YouTube Music")
            }
            return try JSONSerialization.jsonObject(with: data)
        } catch let error as MusicError {
            throw error
        } catch {
            throw MusicError.providerUnavailable("YouTube Music")
        }
    }

    private func bestAudioURL(in value: Any) -> URL? {
        var candidates: [(URL, Int)] = []
        walk(value) { dictionary in
            guard let mime = dictionary["mimeType"] as? String,
                  mime.lowercased().hasPrefix("audio/") else { return false }
            if let raw = dictionary["url"] as? String, let url = URL(string: raw) {
                candidates.append((url, dictionary["bitrate"] as? Int ?? 0))
            }
            return false
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    private func playabilityReason(in value: Any) -> String? {
        guard let root = value as? [String: Any],
              let status = root["playabilityStatus"] as? [String: Any],
              let reason = status["reason"] as? String else { return nil }
        return reason
    }

    private func findString(in value: Any, key: String) -> String? {
        var result: String?
        walk(value) { dictionary in
            if let string = dictionary[key] as? String {
                result = string
                return true
            }
            return false
        }
        return result
    }

    private func walk(_ value: Any, visit: ([String: Any]) -> Bool) {
        if let dictionary = value as? [String: Any] {
            if visit(dictionary) { return }
            for child in dictionary.values { walk(child, visit: visit) }
        } else if let array = value as? [Any] {
            for child in array { walk(child, visit: visit) }
        }
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
        return thumbnails.reversed().compactMap { URL(string: $0["url"] as? String ?? "") }.first
    }

    private func duration(from dictionary: [String: Any]) -> TimeInterval? {
        if let length = dictionary["lengthText"], let text = firstText(length) {
            let parts = text.split(separator: ":").compactMap { Double($0) }
            guard !parts.isEmpty else { return nil }
            return parts.enumerated().reduce(0) { total, item in
                total + item.element * pow(60, Double(parts.count - item.offset - 1))
            }
        }
        return nil
    }

    private func deduplicate(_ tracks: [MusicTrack]) -> [MusicTrack] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.id).inserted }
    }
}

enum MusicError: LocalizedError {
    case providerUnavailable(String)
    case providerMessage(String)
    case streamUnavailable(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .providerUnavailable(provider): return "Không thể kết nối (provider)."
        case let .providerMessage(message): return message
        case let .streamUnavailable(provider): return "Không tìm thấy luồng phát từ (provider)."
        case .invalidResponse: return "Dữ liệu nhà cung cấp không hợp lệ."
        }
    }
}

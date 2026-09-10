import Foundation

actor SoundCloudClient {
    private let session: URLSession
    private let homeURL = URL(string: "https://soundcloud.com")!
    private var inMemoryClientID: String?
    private var clientIDLoadedAt: Date?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ query: String) async throws -> [MusicTrack] {
        let clientID = try await clientID()
        var components = URLComponents(string: "https://api-v2.soundcloud.com/search/tracks")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "offset", value: "0")
        ]
        let data = try await request(components.url!, provider: "SoundCloud")
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.collection.map { track in
            MusicTrack(
                id: String(track.id),
                title: track.title,
                artist: track.user?.username ?? "SoundCloud",
                source: .soundCloud,
                artworkURL: URL(string: track.artworkURL ?? track.user?.avatarURL ?? ""),
                permalinkURL: URL(string: track.permalinkURL ?? ""),
                duration: track.duration.map { TimeInterval($0) / 1000.0 }
            )
        }
    }

    func resolveStream(for track: MusicTrack) async throws -> URL {
        let clientID = try await clientID()
        let url = URL(string: "https://api-v2.soundcloud.com/tracks/\(track.id)/streams?client_id=\(clientID)")!
        let data = try await request(url, provider: "SoundCloud")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusicError.invalidResponse
        }

        let preferredKeys = [
            "http_mp3_128_url",
            "hls_mp3_128_url",
            "hls_aac_160_url",
            "hls_aac_96_url"
        ]
        for key in preferredKeys {
            if let value = object[key] as? String, let streamURL = URL(string: value) {
                return streamURL
            }
        }
        throw MusicError.streamUnavailable("SoundCloud")
    }

    private func clientID() async throws -> String {
        if let inMemoryClientID,
           let loadedAt = clientIDLoadedAt,
           Date().timeIntervalSince(loadedAt) < 6 * 60 * 60 {
            return inMemoryClientID
        }

        let defaults = UserDefaults.standard
        if let cached = defaults.string(forKey: "soundcloud.web.client_id"), !cached.isEmpty {
            inMemoryClientID = cached
            clientIDLoadedAt = Date()
            return cached
        }

        let homeData = try await request(homeURL, provider: "SoundCloud")
        let html = String(decoding: homeData, as: UTF8.self)
        let scriptURLs = extractScriptURLs(from: html)

        if let id = SoundCloudParser.findClientID(in: html) {
            return cacheClientID(id)
        }

        return try await withThrowingTaskGroup(of: String?.self) { group in
            for scriptURL in scriptURLs.prefix(12) {
                group.addTask { [session] in
                    do {
                        let (data, response) = try await session.data(from: scriptURL)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                        return SoundCloudParser.findClientID(in: String(decoding: data, as: UTF8.self))
                    } catch {
                        return nil
                    }
                }
            }

            while let result = try await group.next() {
                if let result {
                    group.cancelAll()
                    return cacheClientID(result)
                }
            }
            throw MusicError.providerUnavailable("SoundCloud Web client ID")
        }
    }

    private func cacheClientID(_ value: String) -> String {
        inMemoryClientID = value
        clientIDLoadedAt = Date()
        UserDefaults.standard.set(value, forKey: "soundcloud.web.client_id")
        return value
    }

    private func request(_ url: URL, provider: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("SimpMusicNative/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MusicError.providerUnavailable(provider)
            }
            return data
        } catch let error as MusicError {
            throw error
        } catch {
            throw MusicError.providerUnavailable(provider)
        }
    }

    private func extractScriptURLs(from html: String) -> [URL] {
        let pattern = #"<script[^>]+src=[\"']([^\"']+\.js[^\"']*)[\"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: html) else { return nil }
            return URL(string: String(html[valueRange]), relativeTo: homeURL)?.absoluteURL
        }
    }

    private struct SearchResponse: Decodable {
        let collection: [SoundCloudTrack]
    }

    private struct SoundCloudTrack: Decodable {
        let id: Int
        let title: String
        let duration: Int?
        let artworkURL: String?
        let permalinkURL: String?
        let user: User?

        enum CodingKeys: String, CodingKey {
            case id, title, duration, user
            case artworkURL = "artwork_url"
            case permalinkURL = "permalink_url"
        }
    }

    private struct User: Decodable {
        let username: String?
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case username
            case avatarURL = "avatar_url"
        }
    }
}

private enum SoundCloudParser {
    static func findClientID(in text: String) -> String? {
        let patterns = [
            #"client_id(?:%3D|=|[\"':\s]+)([A-Za-z0-9]{32})"#,
            #"client_id%3D([A-Za-z0-9]{32})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let valueRange = Range(match.range(at: 1), in: text) {
                return String(text[valueRange])
            }
        }
        return nil
    }
}

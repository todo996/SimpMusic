import Foundation

actor SoundCloudClient {
    private let session: URLSession
    private let homeURL = URL(string: "https://soundcloud.com/")!
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
            URLQueryItem(name: "limit", value: "40"),
            URLQueryItem(name: "offset", value: "0")
        ]
        let data = try await request(components.url!, provider: "SoundCloud")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let collection = root["collection"] as? [[String: Any]] else {
            throw MusicError.invalidResponse
        }
        return collection.compactMap { track in
            guard let id = track["id"] as? Int,
                  let title = track["title"] as? String else { return nil }
            let user = track["user"] as? [String: Any]
            let artwork = (track["artwork_url"] as? String) ?? (user?["avatar_url"] as? String)
            return MusicTrack(
                id: "sc:\(id)",
                title: title,
                artist: user?["username"] as? String ?? "SoundCloud",
                album: nil,
                source: .soundCloud,
                artworkURL: URL(string: artwork?.replacingOccurrences(of: "-large", with: "-t500x500") ?? ""),
                permalinkURL: URL(string: track["permalink_url"] as? String ?? ""),
                duration: (track["duration"] as? NSNumber).map { $0.doubleValue / 1000 }
            )
        }
    }

    func resolveStream(for track: MusicTrack) async throws -> URL {
        let clientID = try await clientID()
        let numericID = track.id.replacingOccurrences(of: "sc:", with: "")
        var components = URLComponents(string: "https://api-v2.soundcloud.com/tracks/\(numericID)/streams")!
        components.queryItems = [URLQueryItem(name: "client_id", value: clientID)]
        let data = try await request(components.url!, provider: "SoundCloud")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusicError.invalidResponse
        }

        for key in ["http_mp3_128_url", "preview_mp3_128_url", "hls_mp3_128_url"] {
            if let raw = root[key] as? String, let url = URL(string: raw) { return url }
        }

        guard let media = root["media"] as? [String: Any],
              let transcodings = media["transcodings"] as? [[String: Any]] else {
            throw MusicError.streamUnavailable("SoundCloud")
        }
        let ranked = transcodings.sorted { left, right in
            rank(left) < rank(right)
        }
        for transcoding in ranked {
            guard let raw = transcoding["url"] as? String,
                  var transcodingURL = URL(string: raw) else { continue }
            var query = URLComponents(url: transcodingURL, resolvingAgainstBaseURL: false)
            var items = query?.queryItems ?? []
            items.append(URLQueryItem(name: "client_id", value: clientID))
            query?.queryItems = items
            transcodingURL = query?.url ?? transcodingURL
            do {
                let resolved = try await request(transcodingURL, provider: "SoundCloud")
                if let object = try JSONSerialization.jsonObject(with: resolved) as? [String: Any],
                   let stream = object["url"] as? String,
                   let url = URL(string: stream) {
                    return url
                }
            } catch {
                continue
            }
        }
        throw MusicError.streamUnavailable("SoundCloud")
    }

    private func rank(_ transcoding: [String: Any]) -> Int {
        let format = transcoding["format"] as? [String: Any]
        let protocolName = format?["protocol"] as? String ?? ""
        let mime = format?["mime_type"] as? String ?? ""
        if protocolName == "progressive" && mime.contains("mpeg") { return 0 }
        if protocolName == "progressive" { return 1 }
        if protocolName == "hls" { return 2 }
        return 3
    }

    private func clientID() async throws -> String {
        if let inMemoryClientID,
           let loadedAt = clientIDLoadedAt,
           Date().timeIntervalSince(loadedAt) < 12 * 60 * 60 {
            return inMemoryClientID
        }
        if let cached = UserDefaults.standard.string(forKey: "simpmusic.soundcloud.client_id"),
           Self.isValidClientID(cached),
           await isValid(cached) {
            inMemoryClientID = cached
            clientIDLoadedAt = Date()
            return cached
        }

        let html = try await request(homeURL, provider: "SoundCloud").flatMapString()
        var candidates = Self.findClientIDs(in: html)
        for script in Self.scriptURLs(in: html).prefix(16) {
            if let source = try? await request(script, provider: "SoundCloud").flatMapString() {
                candidates.append(contentsOf: Self.findClientIDs(in: source))
            }
        }
        for candidate in candidates {
            if await isValid(candidate) {
                inMemoryClientID = candidate
                clientIDLoadedAt = Date()
                UserDefaults.standard.set(candidate, forKey: "simpmusic.soundcloud.client_id")
                return candidate
            }
        }
        throw MusicError.providerUnavailable("SoundCloud Web client ID")
    }

    private func isValid(_ candidate: String) async -> Bool {
        var components = URLComponents(string: "https://api-v2.soundcloud.com/search/tracks")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: candidate),
            URLQueryItem(name: "q", value: "test"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return false }
        guard let result = try? await session.data(from: url),
              let response = result.1 as? HTTPURLResponse else { return false }
        return response.statusCode == 200
    }

    private func request(_ url: URL, provider: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("SimpMusic-iOS/1.0", forHTTPHeaderField: "User-Agent")
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

    private static func scriptURLs(in html: String) -> [URL] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]+src=[\"']([^\"']+\.js[^\"']*)[\"']"#,
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: html) else { return nil }
            let value = String(html[valueRange])
            if value.hasPrefix("//") { return URL(string: "https:\(value)") }
            if value.hasPrefix("/") { return URL(string: "https://soundcloud.com\(value)") }
            return URL(string: value, relativeTo: URL(string: "https://soundcloud.com/")!)?.absoluteURL
        }.filter { url in
            guard let host = url.host else { return false }
            return host == "soundcloud.com" || host.hasSuffix(".soundcloud.com") || host.hasSuffix(".sndcdn.com")
        }
    }

    private static func findClientIDs(in text: String) -> [String] {
        let patterns = [
            #"(?i)client[_-]?id\s*[=:]\s*[\"']([A-Za-z0-9_-]{20,64})"#,
            #"(?i)client[_-]?(?:%3[dD]|=)([A-Za-z0-9_-]{20,64})"#
        ]
        var result: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                if let valueRange = Range(match.range(at: 1), in: text) {
                    let value = String(text[valueRange])
                    if isValidClientID(value) { result.append(value) }
                }
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    private static func isValidClientID(_ value: String) -> Bool {
        value.count >= 20 && value.count <= 64 && value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }
}

private extension Data {
    func flatMapString() -> String {
        String(decoding: self, as: UTF8.self)
    }
}

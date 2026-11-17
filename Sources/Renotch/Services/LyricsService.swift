import Foundation

/// Fetches and caches synchronized lyrics for the currently playing track.
///
/// Lyrics come from LRCLIB (https://lrclib.net), a free, no-auth community source
/// that returns time-synced LRC text keyed by artist + title + album + duration.
/// This works uniformly for both Apple Music and Spotify since neither exposes
/// lyrics through its automation interface.
@MainActor
final class LyricsService: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plainLines: [String] = []
    @Published private(set) var state: LyricsState = .idle
    @Published private(set) var trackKey: String?

    /// In-memory cache keyed by `MusicTrack.cacheKey`, storing JSON-encoded lines.
    private static let memoryCache = NSCache<NSString, NSData>()
    private var loadTask: Task<Void, Never>?
    private var requestID = UUID()

    private static let diskDirectory: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Renotch/Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    // MARK: - Public API

    func load(for track: MusicTrack?) {
        guard let track, !track.title.isEmpty, track.title != "Unknown title" else {
            clear()
            return
        }
        let key = track.cacheKey
        guard key != trackKey else { return }
        trackKey = key
        requestID = UUID()
        let currentRequest = requestID

        if let cached = Self.cachedLines(for: key) {
            apply(synced: cached, plain: [], state: .loaded, request: currentRequest)
            return
        }

        state = .loading
        lines = []
        plainLines = []
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let result = await Self.fetch(track: track)
            guard !Task.isCancelled, let self, currentRequest == self.requestID else { return }
            switch result {
            case let .synced(lrc):
                let parsed = Self.parseLRC(lrc)
                Self.store(parsed, for: key)
                self.apply(synced: parsed, plain: [], state: .loaded, request: currentRequest)
            case let .plain(text):
                self.apply(synced: [], plain: Self.splitPlain(text), state: .unavailable, request: currentRequest)
            case .none:
                self.apply(synced: [], plain: [], state: .unavailable, request: currentRequest)
            }
        }
    }

    func clear() {
        loadTask?.cancel()
        trackKey = nil
        lines = []
        plainLines = []
        state = .idle
    }

    /// Index of the lyric line currently active at `position`, or nil if none yet.
    func currentIndex(at position: TimeInterval) -> Int? {
        Self.index(of: lines, at: position)
    }

    /// Pure binary search: last line whose `time` is <= `position`.
    nonisolated static func index(of lines: [LyricLine], at position: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    func currentLine(at position: TimeInterval) -> String? {
        guard let index = currentIndex(at: position), index < lines.count else { return nil }
        return lines[index].text
    }

    // MARK: - Apply

    private func apply(
        synced: [LyricLine],
        plain: [String],
        state: LyricsState,
        request: UUID
    ) {
        guard request == requestID else { return }
        lines = synced
        plainLines = plain
        self.state = state
    }

    // MARK: - Fetching

    private enum LyricsFetchResult: Sendable {
        case synced(String)
        case plain(String)
        case none
    }

    nonisolated private static func fetch(track: MusicTrack) async -> LyricsFetchResult {
        let duration = Int(track.duration.rounded())
        if let result = await fetchGet(track: track, duration: duration) {
            return result
        }
        return await fetchSearch(track: track, duration: duration)
    }

    nonisolated private static func fetchGet(
        track: MusicTrack,
        duration: Int
    ) async -> LyricsFetchResult? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: duration > 0 ? String(duration) : nil)
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
                return .synced(synced)
            }
            if let plain = json["plainLyrics"] as? String, !plain.isEmpty {
                return .plain(plain)
            }
        } catch {
            return nil
        }
        return nil
    }

    nonisolated private static func fetchSearch(
        track: MusicTrack,
        duration: Int
    ) async -> LyricsFetchResult {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        guard let url = components?.url else { return .none }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !results.isEmpty else {
                return .none
            }

            let tolerance = 3
            let durationMatched = results.first { result in
                let resultDuration = (result["duration"] as? Int) ?? 0
                return duration > 0 && abs(resultDuration - duration) <= tolerance
            }
            for result in [durationMatched, results.first].compactMap({ $0 }) {
                if let synced = result["syncedLyrics"] as? String, !synced.isEmpty {
                    return .synced(synced)
                }
                if let plain = result["plainLyrics"] as? String, !plain.isEmpty {
                    return .plain(plain)
                }
            }
        } catch {
            return .none
        }
        return .none
    }

    // MARK: - LRC Parsing

    /// Parses LRC text into timestamped lines, applying any `[offset:]` tag and
    /// expanding multi-timestamp lines into separate entries.
    nonisolated static func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        var offset: TimeInterval = 0
        let timestampPattern = #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: timestampPattern) else { return [] }

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[offset:") {
                if let range = line.range(of: #"-?\d+"#, options: .regularExpression),
                   let ms = Double(line[range]) {
                    offset = ms / 1_000.0
                }
                continue
            }

            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard let lastMatch = matches.last else { continue }

            let textStart = lastMatch.range.location + lastMatch.range.length
            let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for match in matches {
                let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                let fractionString = match.range(at: 3).location != NSNotFound
                    ? nsLine.substring(with: match.range(at: 3))
                    : "0"
                let fraction = (Double(fractionString) ?? 0) / pow(10, Double(fractionString.count))
                let time = minutes * 60 + seconds + fraction + offset
                lines.append(LyricLine(time: max(0, time), text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    nonisolated private static func splitPlain(_ plain: String) -> [String] {
        plain.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Caching

    private static func cachedLines(for key: String) -> [LyricLine]? {
        if let cached = memoryCache.object(forKey: key as NSString) {
            return decode(cached as Data)
        }
        let url = diskFileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let lines = decode(data) else {
            return nil
        }
        memoryCache.setObject(data as NSData, forKey: key as NSString)
        return lines
    }

    private static func store(_ lines: [LyricLine], for key: String) {
        guard let data = try? JSONEncoder().encode(lines) else { return }
        memoryCache.setObject(data as NSData, forKey: key as NSString)
        try? data.write(to: diskFileURL(for: key), options: .atomic)
    }

    private static func decode(_ data: Data) -> [LyricLine]? {
        try? JSONDecoder().decode([LyricLine].self, from: data)
    }

    private static func diskFileURL(for key: String) -> URL {
        let filename = key.data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "") ?? key
        return diskDirectory.appendingPathComponent("\(filename).json")
    }
}

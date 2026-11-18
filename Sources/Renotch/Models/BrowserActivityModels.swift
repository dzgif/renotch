import Foundation

struct BrowserMediaActivity: Equatable, Identifiable, Sendable {
    let sessionID: String
    let title: String
    let channel: String
    let pageURL: URL?
    let thumbnailURL: URL?
    let isPlaying: Bool
    let position: TimeInterval
    let duration: TimeInterval
    let updatedAt: Date

    var id: String { sessionID }

    /// Friendly platform name derived from the page host (YouTube, SoundCloud, ...).
    var sourceName: String {
        guard let host = pageURL?.host?.lowercased() else { return "Media" }
        let cleaned = host.replacingOccurrences(of: "www.", with: "")
        if cleaned.contains("youtube") || cleaned == "youtu.be" { return "YouTube" }
        if cleaned.contains("soundcloud") { return "SoundCloud" }
        if cleaned.contains("spotify") { return "Spotify" }
        if cleaned.contains("netflix") { return "Netflix" }
        if cleaned.contains("vimeo") { return "Vimeo" }
        return cleaned.split(separator: ".").first.map { $0.capitalized } ?? "Media"
    }

    var progress: Double? {
        guard duration > 0 else { return nil }
        return (position / duration).clamped(to: 0...1)
    }
}

enum BrowserDownloadState: String, Codable, Sendable {
    case inProgress = "in_progress"
    case complete
    case interrupted
}

struct BrowserDownloadActivity: Equatable, Identifiable, Sendable {
    let id: Int
    let filename: String
    let sourceURL: URL?
    let bytesReceived: Int64
    let totalBytes: Int64
    let state: BrowserDownloadState
    let paused: Bool
    let updatedAt: Date

    var displayName: String {
        let name = URL(fileURLWithPath: filename).lastPathComponent
        return name.isEmpty ? "Download" : name
    }

    var progress: Double? {
        guard totalBytes > 0 else { return nil }
        return (Double(bytesReceived) / Double(totalBytes)).clamped(to: 0...1)
    }

    var isFinished: Bool { state != .inProgress }
}

enum BrowserActivityPresentation: Hashable, Sendable {
    case media(String, Bool, Int)
    case download(Int, BrowserDownloadState, Int64)
}

enum AdaptiveMediaSource: String, Equatable, Sendable {
    case browser
    case music
    case remote
}

enum AdaptiveMediaArbitrator {
    static func resolve(
        browserAvailable: Bool,
        browserIsPlaying: Bool,
        browserActivation: Date,
        musicIsPlaying: Bool,
        musicActivation: Date,
        remoteIsPlaying: Bool = false,
        remoteActivation: Date = .distantPast
    ) -> AdaptiveMediaSource? {
        var winner: (source: AdaptiveMediaSource, activation: Date)?
        func consider(_ source: AdaptiveMediaSource, _ isPlaying: Bool, _ activation: Date) {
            guard isPlaying else { return }
            if winner == nil || activation >= winner!.activation {
                winner = (source, activation)
            }
        }
        consider(.browser, browserIsPlaying, browserActivation)
        consider(.music, musicIsPlaying, musicActivation)
        consider(.remote, remoteIsPlaying, remoteActivation)
        return winner?.source
    }
}

import Foundation

/// A single synced lyric line with its playback timestamp.
struct LyricLine: Codable, Equatable, Sendable, Identifiable {
    let time: TimeInterval
    let text: String

    var id: String { "\(time)-\(text)" }
}

/// High-level state of the lyric pipeline.
enum LyricsState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case unavailable
}

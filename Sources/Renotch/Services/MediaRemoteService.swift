import AppKit
import Darwin
import Foundation

/// Reads the system-wide "now playing" info via the private MediaRemote
/// framework — the same source macOS Control Center uses. This lets the notch
/// surface playback from any app (browser SoundCloud/YouTube, VLC, etc.)
/// without a browser extension. Apple Music and Spotify are filtered out here
/// because `MusicService` already drives them with richer controls.
@MainActor
final class MediaRemoteService: ObservableObject {
    struct NowPlaying {
        let title: String
        let artist: String
        let album: String
        let artwork: NSImage?
        let duration: TimeInterval
        let position: TimeInterval
        let isPlaying: Bool
        let appName: String
    }

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var playbackActivationDate = Date.distantPast

    private var pollingTimer: Timer?
    private var artworkCache: [String: NSImage] = [:]

    private typealias GetNowPlayingInfo = @convention(c) (
        DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void
    ) -> Void
    private typealias GetIsPlaying = @convention(c) (
        DispatchQueue, @escaping @convention(block) (Bool) -> Void
    ) -> Void
    private typealias GetDisplayName = @convention(c) (
        DispatchQueue, @escaping @convention(block) (CFString?) -> Void
    ) -> Void

    private let getInfo: GetNowPlayingInfo?
    private let getIsPlaying: GetIsPlaying?
    private let getDisplayName: GetDisplayName?

    private static let excludedAppNames: Set<String> = ["Music", "Spotify"]

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        if let handle {
            getInfo = Self.load(handle, "MRMediaRemoteGetNowPlayingInfo")
            getIsPlaying = Self.load(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
            getDisplayName = Self.load(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayName")
        } else {
            getInfo = nil
            getIsPlaying = nil
            getDisplayName = nil
        }
        startPolling()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    func pause() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func resume() {
        guard pollingTimer == nil else { return }
        startPolling()
    }

    private static func load<T>(_ handle: UnsafeMutableRawPointer, _ symbol: String) -> T? {
        guard let fnPointer = symbol.withCString({ dlsym(handle, $0) }) else { return nil }
        return unsafeBitCast(fnPointer, to: T.self)
    }

    private func startPolling() {
        pollingTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.5
        pollingTimer = timer
        refresh()
    }

    private func refresh() {
        guard let getInfo, let getIsPlaying, let getDisplayName else {
            nowPlaying = nil
            return
        }

        getIsPlaying(.main) { [weak self] isPlaying in
            guard isPlaying else {
                Task { @MainActor in self?.nowPlaying = nil }
                return
            }
            getDisplayName(.main) { [weak self] displayName in
                let appName = displayName as String? ?? ""
                guard !Self.excludedAppNames.contains(appName) else {
                    Task { @MainActor in self?.nowPlaying = nil }
                    return
                }
                getInfo(.main) { [weak self] info in
                    let raw = Self.parse(info: info, appName: appName)
                    Task { @MainActor in self?.apply(raw) }
                }
            }
        }
    }

    private struct RawNowPlaying {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let position: TimeInterval
        let artworkData: Data?
        let appName: String
    }

    private nonisolated static func parse(info: CFDictionary?, appName: String) -> RawNowPlaying? {
        guard let dict = info as? [String: Any] else { return nil }
        guard let title = (dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty else {
            return nil
        }
        let artist = (dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? ""
        let album = (dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String) ?? ""
        let duration = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
        let position = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
        let artworkData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        return RawNowPlaying(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position,
            artworkData: artworkData,
            appName: appName
        )
    }

    private func apply(_ raw: RawNowPlaying?) {
        guard let raw else {
            nowPlaying = nil
            return
        }
        let cacheKey = "\(raw.title)|\(raw.artist)"
        let artwork: NSImage?
        if let cached = artworkCache[cacheKey] {
            artwork = cached
        } else if let data = raw.artworkData, let image = NSImage(data: data) {
            artworkCache[cacheKey] = image
            artwork = image
        } else {
            artwork = nil
        }
        let next = NowPlaying(
            title: raw.title,
            artist: raw.artist,
            album: raw.album,
            artwork: artwork,
            duration: raw.duration,
            position: raw.position,
            isPlaying: true,
            appName: raw.appName
        )
        if nowPlaying?.title != next.title || nowPlaying?.artist != next.artist {
            playbackActivationDate = Date()
        }
        nowPlaying = next
    }
}

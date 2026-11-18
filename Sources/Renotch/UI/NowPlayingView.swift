import AppKit
import SwiftUI

/// Expanded now-playing panel for the MediaRemote source (any non-Apple/Spotify
/// app: browser SoundCloud, YouTube, VLC, etc.).
struct NowPlayingView: View {
    let nowPlaying: MediaRemoteService.NowPlaying

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 13) {
                ZStack {
                    if let artwork = nowPlaying.artwork {
                        ZStack {
                            Image(nsImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 18)
                                .scaleEffect(1.18)
                                .opacity(0.55)
                                .offset(y: 4)

                            Image(nsImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 9)
                                .scaleEffect(1.06)
                                .opacity(0.75)
                                .offset(y: 2)
                        }
                        .frame(width: 104, height: 58)
                        .allowsHitTesting(false)
                    }

                    Group {
                        if let artwork = nowPlaying.artwork {
                            Image(nsImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            ZStack {
                                Color.notchAccent
                                Image(systemName: "music.note")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .frame(width: 104, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                    }
                    .shadow(color: .black.opacity(nowPlaying.artwork != nil ? 0.35 : 0), radius: 6, y: 3)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.rectangle.fill")
                        Text(sourceLabel)
                            .tracking(0.8)
                        Circle()
                            .fill(nowPlaying.isPlaying ? Color.notchAccent : Color.white.opacity(0.35))
                            .frame(width: 4, height: 4)
                        Text(nowPlaying.isPlaying ? "Playing" : "Paused")
                    }
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(nowPlaying.isPlaying ? Color.notchAccent : Color.notchMuted)

                    Text(nowPlaying.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(nowPlaying.artist.isEmpty ? nowPlaying.album : nowPlaying.artist)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.notchMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let progress = progress {
                HStack(spacing: 8) {
                    Text(formatted(nowPlaying.position))
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule().fill(Color.notchAccent).frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 3)
                    Text("−\(formatted(max(0, nowPlaying.duration - nowPlaying.position)))")
                }
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(Color.notchMuted)
                .monospacedDigit()
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sourceLabel: String {
        nowPlaying.appName.isEmpty ? "NOW PLAYING" : nowPlaying.appName.uppercased()
    }

    private var progress: Double? {
        guard nowPlaying.duration > 0 else { return nil }
        return (nowPlaying.position / nowPlaying.duration).clamped(to: 0...1)
    }

    private func formatted(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

/// Compact single-line now-playing chip for the MediaRemote source.
struct CompactNowPlayingView: View {
    let nowPlaying: MediaRemoteService.NowPlaying

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if let artwork = nowPlaying.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.notchAccent
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(nowPlaying.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(nowPlaying.isPlaying ? Color.notchAccent : Color.white.opacity(0.35))
                        .frame(width: 5, height: 5)
                    Text(nowPlaying.isPlaying
                        ? (nowPlaying.artist.isEmpty ? nowPlaying.appName : nowPlaying.artist)
                        : "Paused")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color.notchMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: nowPlaying.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(nowPlaying.isPlaying ? Color.notchAccent : .secondary)
                .frame(width: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(nowPlaying.appName), \(nowPlaying.title), \(nowPlaying.isPlaying ? "playing" : "paused")")
    }
}

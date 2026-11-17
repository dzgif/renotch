import SwiftUI

/// Full synced-lyrics panel shown in the expanded music section.
/// Auto-scrolls to keep the active line centered and lets the user tap a line to seek.
struct LyricsView: View {
    @ObservedObject var music: MusicService
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        Group {
            switch lyrics.state {
            case .idle, .loading:
                loadingView
            case .loaded:
                syncedLyrics
            case .unavailable:
                if lyrics.plainLines.isEmpty {
                    unavailableView
                } else {
                    plainLyrics
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Synced lyrics

    private var syncedLyrics: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 13) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        Text(line.text)
                            .font(.system(size: index == currentIndex ? 15 : 13, weight: index == currentIndex ? .semibold : .regular))
                            .foregroundStyle(index == currentIndex ? .white : Color.notchMuted)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { music.seek(to: line.time) }
                            .animation(.easeOut(duration: 0.2), value: currentIndex)
                    }
                }
                .padding(.vertical, 34)
                .padding(.horizontal, 10)
            }
            .onChange(of: currentIndex) { newIndex in
                guard let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Plain (unsynced) fallback

    private var plainLyrics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lyrics.plainLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.notchMuted)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.notchAccent)
            Text("Loading lyrics…")
                .font(.system(size: 11))
                .foregroundStyle(Color.notchMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableView: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.quote")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
            Text("No lyrics found")
                .font(.system(size: 13, weight: .semibold))
            Text("Synced lyrics aren't available for this track.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.notchMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var currentIndex: Int? {
        lyrics.currentIndex(at: music.position)
    }
}

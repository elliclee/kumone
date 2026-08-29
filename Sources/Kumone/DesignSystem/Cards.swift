import SwiftUI

// MARK: - Cover card (playlists / albums)

struct CoverCard: View {
    let coverURL: URL?
    let title: String
    var subtitle: String?
    var playCount: Int = 0
    var size: CGFloat = Theme.Layout.cardSize
    var onPlay: (() -> Void)?
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    coverArtwork
                        .frame(width: size, height: size)
                    #if os(macOS)
                    if playCount > 0 {
                        PlayCountBadge(count: playCount)
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    #endif
                    if let onPlay {
                        PlayOverlayButton(visible: isHovering, action: onPlay)
                            .padding(8)
                    }
                }
                .frame(width: size, height: size)

                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Typography.cardSubtitle)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.interactiveCard)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var coverArtwork: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous)
        #if os(macOS)
        CachedAsyncImage(url: coverURL)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        #else
        CachedAsyncImage(url: coverURL)
            .clipShape(shape)
        #endif
    }
}

// MARK: - Artist card (circular)

struct ArtistCard: View {
    let artist: ArtistSummary
    var size: CGFloat = 128
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 10) {
                CachedAsyncImage(url: artist.picUrl?.resizedImageURL(256))
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    #if os(macOS)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                    #endif
                Text(artist.name)
                    .font(Theme.Typography.cardTitle)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .frame(width: size + 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.interactiveCard)
    }
}

// MARK: - Horizontal shelf

/// A horizontal scroll section whose track reaches the column edges;
/// the resting inset lives inside the HStack (kaset's slide-under trick).
struct Shelf<Content: View>: View {
    let title: LocalizedStringKey
    var seeAll: (() -> Void)?
    var spacing: CGFloat = Theme.Layout.shelfSpacing
    /// Height of one row of cards.
    ///
    /// Supplying it lets the shelf build its cards lazily, which matters more
    /// than it sounds: a plain `HStack` instantiates every card in the shelf and
    /// keeps it in the responder tree, so hit testing walks all of them on every
    /// frame of a *vertical* scroll — including the ones scrolled off the side
    /// and never seen. Measured at roughly half the cost of scrolling the home
    /// page. It has to be stated rather than measured because a `LazyHStack`
    /// reports no height until something has been scrolled into view, which
    /// leaves the enclosing horizontal ScrollView with nothing to lay out
    /// against and collapses the whole page.
    var rowHeight: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            SectionHeader(title: title, action: seeAll)
                .padding(.horizontal, Theme.Layout.contentInset)
            ScrollView(.horizontal, showsIndicators: false) {
                cards
                    .padding(.vertical, 6)
            }
            #if os(iOS)
            .frame(height: rowHeight.map { $0 + 12 })
            #endif
            .compatScrollClipDisabled()
        }
    }

    private var headerSpacing: CGFloat {
        #if os(iOS)
        return 8
        #else
        return 14
        #endif
    }

    private var edgeInset: some View {
        Color.clear.frame(width: max(0, Theme.Layout.contentInset - spacing), height: 1)
    }

    @ViewBuilder
    private var cards: some View {
        if let rowHeight {
            LazyHStack(alignment: .top, spacing: spacing) {
                edgeInset
                content()
                edgeInset
            }
            .frame(height: rowHeight)
        } else {
            HStack(alignment: .top, spacing: spacing) {
                edgeInset
                content()
                edgeInset
            }
        }
    }
}

// MARK: - Adaptive card grid

struct CardGrid<Content: View>: View {
    var minWidth: CGFloat = Theme.Layout.cardSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading, spacing: 24
        ) {
            content()
        }
    }

    private var columns: [GridItem] {
        #if os(iOS)
        return [
            GridItem(.flexible(), spacing: Theme.Layout.gridSpacing, alignment: .topLeading),
            GridItem(.flexible(), spacing: Theme.Layout.gridSpacing, alignment: .topLeading),
        ]
        #else
        return [
            GridItem(.adaptive(minimum: minWidth, maximum: minWidth + 40),
                     spacing: Theme.Layout.gridSpacing, alignment: .top)
        ]
        #endif
    }
}

// MARK: - Error / empty states

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("加载失败").font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

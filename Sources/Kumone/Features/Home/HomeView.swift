import SwiftUI

enum FollowedArtistReleaseSelector {
    static let artistLimit = 12
    static let albumsPerArtist = 3
    static let releaseLimit = 12

    static func recentCutoff(referenceDate: Date = .now, calendar: Calendar = .current) -> Int {
        let cutoff = calendar.date(byAdding: .year, value: -2, to: referenceDate) ?? referenceDate
        return Int(cutoff.timeIntervalSince1970 * 1_000)
    }

    static func select(
        from batches: [[AlbumSummary]],
        newerThan cutoff: Int,
        limit: Int = releaseLimit
    ) -> [AlbumSummary] {
        var seen = Set<Int>()
        return batches
            .flatMap { $0 }
            .filter { $0.publishTime >= cutoff }
            .sorted {
                if $0.publishTime == $1.publishTime { return $0.id > $1.id }
                return $0.publishTime > $1.publishTime
            }
            .filter { seen.insert($0.id).inserted }
            .prefix(limit)
            .map { $0 }
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    /// Shared so the loaded page survives sidebar switches (no skeleton flash).
    static let shared = HomeViewModel()

    enum State {
        case idle, loading, loaded
        case error(String)
    }

    /// The personalized radar family — global playlist IDs whose content is
    /// generated per logged-in account (same list YesPlayMusic special-cases).
    static let radarPlaylistIDs = [
        3_136_952_023, // 私人雷达
        2_829_883_282, // 华语私人雷达
        2_829_816_518, // 欧美私人雷达
        2_829_896_389, // 日系私人雷达
    ]

    struct RadarPlaylist: Identifiable, Hashable {
        let id: Int
        let title: String
        let subtitle: String?
        let coverURL: String?
    }

    @Published var state: State = .idle
    @Published var recommendPlaylists: [PlaylistSummary] = []
    @Published var radarPlaylists: [RadarPlaylist] = []
    @Published var toplists: [ToplistItem] = []
    @Published var newAlbums: [AlbumSummary] = []
    @Published var followedArtistReleases: [AlbumSummary] = []
    @Published var dailyFirstCover: String?
    private var loadedForContext: LoadContext?

    private struct LoadContext: Equatable {
        let loggedIn: Bool
        let followedArtistIDs: [Int]
    }

    func load(loggedIn: Bool, followedArtistIDs: [Int]) async {
        let context = LoadContext(loggedIn: loggedIn, followedArtistIDs: followedArtistIDs)
        if case .loaded = state, loadedForContext == context { return }
        state = .loading
        followedArtistReleases = []

        async let playlistsTask = fetchRecommendPlaylists(loggedIn: loggedIn)
        async let toplistsTask = try? NeteaseAPI.toplists()
        async let albumsTask = try? NeteaseAPI.newAlbums(limit: 20)

        let playlists = await playlistsTask
        let toplists = (await toplistsTask ?? []).filter {
            [19_723_756, 3_779_629, 2_884_035, 3_778_678, 60198].contains($0.id)
        }
        let newAlbums = await albumsTask ?? []

        // `.task(id:)` cancels the anonymous launch request once account
        // restoration finishes. A cancelled request is not a network error.
        guard !Task.isCancelled else { return }

        var nextDailyFirstCover: String?
        var nextRadarPlaylists: [RadarPlaylist] = []
        if loggedIn {
            if let daily = try? await NeteaseAPI.dailyRecommendSongs() {
                nextDailyFirstCover = daily.first?.album.picUrl
            }
            nextRadarPlaylists = await fetchRadarPlaylists()
        }

        guard !Task.isCancelled else { return }

        recommendPlaylists = playlists
        self.toplists = toplists
        self.newAlbums = newAlbums
        dailyFirstCover = nextDailyFirstCover
        radarPlaylists = nextRadarPlaylists

        let hasContent = !playlists.isEmpty || !toplists.isEmpty || !newAlbums.isEmpty
        state = hasContent ? .loaded : .error(String(localized: "网络连接失败"))
        if hasContent { loadedForContext = context }

        guard hasContent, loggedIn, !followedArtistIDs.isEmpty else { return }
        let releases = await fetchFollowedArtistReleases(artistIDs: followedArtistIDs)
        guard !Task.isCancelled, loadedForContext == context else { return }
        followedArtistReleases = releases
    }

    func reload(loggedIn: Bool, followedArtistIDs: [Int]) async {
        state = .idle
        await load(loggedIn: loggedIn, followedArtistIDs: followedArtistIDs)
    }

    private func fetchFollowedArtistReleases(artistIDs: [Int]) async -> [AlbumSummary] {
        let ids = Array(artistIDs.prefix(FollowedArtistReleaseSelector.artistLimit))
        var batches: [[AlbumSummary]] = []

        // Four requests at a time keeps the secondary shelf from flooding the
        // service. The primary home content is already visible while this runs.
        for start in stride(from: 0, to: ids.count, by: 4) {
            guard !Task.isCancelled else { return [] }
            let end = min(start + 4, ids.count)
            let chunk = Array(ids[start..<end])
            let next = await withTaskGroup(of: [AlbumSummary].self, returning: [[AlbumSummary]].self) { group in
                for id in chunk {
                    group.addTask {
                        let response = try? await NeteaseAPI.artistAlbums(
                            id: id,
                            limit: FollowedArtistReleaseSelector.albumsPerArtist
                        )
                        return response?.hotAlbums ?? []
                    }
                }

                var albums: [[AlbumSummary]] = []
                for await result in group { albums.append(result) }
                return albums
            }
            batches += next
        }

        return FollowedArtistReleaseSelector.select(
            from: batches,
            newerThan: FollowedArtistReleaseSelector.recentCutoff()
        )
    }

    private func fetchRadarPlaylists() async -> [RadarPlaylist] {
        let briefs = await withTaskGroup(of: (Int, NeteaseAPI.PlaylistBrief.Body?).self) { group in
            for id in Self.radarPlaylistIDs {
                group.addTask {
                    (id, try? await NeteaseAPI.playlistBrief(id: id))
                }
            }
            var byID: [Int: NeteaseAPI.PlaylistBrief.Body] = [:]
            for await (id, brief) in group {
                if let brief { byID[id] = brief }
            }
            return byID
        }
        return Self.radarPlaylistIDs.compactMap { id in
            guard let brief = briefs[id] else { return nil }
            // Names arrive as "今天从《…》听起|私人雷达" — split into title/subtitle.
            let parts = (brief.name ?? "").components(separatedBy: "|")
            let title = parts.count > 1 ? parts.last! : (brief.name ?? String(localized: "雷达歌单"))
            let subtitle = parts.count > 1 ? parts.dropLast().joined(separator: "|") : nil
            return RadarPlaylist(id: id, title: title, subtitle: subtitle, coverURL: brief.coverImgUrl)
        }
    }

    private func fetchRecommendPlaylists(loggedIn: Bool) async -> [PlaylistSummary] {
        if loggedIn {
            async let recommend = try? NeteaseAPI.recommendResource()
            async let personalized = try? NeteaseAPI.personalizedPlaylists(limit: 30)
            let head = await recommend ?? []
            let tail = await personalized ?? []
            var seen = Set<Int>()
            return (head + tail).filter { seen.insert($0.id).inserted }
        }
        return (try? await NeteaseAPI.personalizedPlaylists(limit: 30)) ?? []
    }
}

struct HomeView: View {
    /// Kept behind a local switch so the shelf can be restored without
    /// rebuilding its presentation and navigation behavior.
    private static let showsNewAlbums = false

    private struct LoadContext: Hashable {
        let isBootstrapped: Bool
        let isLoggedIn: Bool
        let followedArtistIDs: [Int]
    }

    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var player: PlayerService
    @StateObject private var model = HomeViewModel.shared

    private var loadContext: LoadContext {
        LoadContext(
            isBootstrapped: account.isBootstrapped,
            isLoggedIn: account.isLoggedIn,
            followedArtistIDs: account.isLoggedIn ? account.likedArtists.map(\.id) : []
        )
    }

    var body: some View {
        ScrollView {
            switch model.state {
            case .idle, .loading:
                loadingBody
            case .error(let message):
                ErrorStateView(message: message) {
                    Task {
                        await model.reload(
                            loggedIn: account.isLoggedIn,
                            followedArtistIDs: account.likedArtists.map(\.id)
                        )
                    }
                }
                .frame(minHeight: 400)
            case .loaded:
                loadedBody
            }
        }
        .navigationTitle("推荐")
        .task(id: loadContext) {
            let context = loadContext
            guard context.isBootstrapped else { return }
            await model.load(
                loggedIn: context.isLoggedIn,
                followedArtistIDs: context.followedArtistIDs
            )
        }
    }

    private var loadingBody: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonView(cornerRadius: Theme.Radius.large)
                        .frame(width: 230, height: 132)
                }
            }
            SkeletonShelf()
            SkeletonShelf()
        }
        .padding(Theme.Layout.contentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadedBody: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            // Anonymous users go straight to recommended playlists;
            // the login entry lives in the sidebar / 我的 tab only.
            if account.isLoggedIn {
                featureCards
                    .padding(.top, 8)
            }

            if !model.recommendPlaylists.isEmpty {
                Shelf(title: "推荐歌单", rowHeight: Theme.Layout.compactCoverShelfHeight) {
                    ForEach(Array(model.recommendPlaylists.prefix(12).enumerated()), id: \.element.id) { index, playlist in
                        playlistCard(playlist)
                            .staggeredAppearance(index: index, id: "home-rec-\(playlist.id)")
                    }
                }
            }

            if !model.radarPlaylists.isEmpty {
                Shelf(title: "雷达歌单", rowHeight: Theme.Layout.coverShelfHeight) {
                    ForEach(model.radarPlaylists) { radar in
                        NavigationLink(value: Destination.playlist(radar.id)) {
                            CoverCardBody(
                                coverURL: radar.coverURL?.resizedImageURL(384),
                                title: radar.title,
                                subtitle: radar.subtitle
                            ) {
                                playPlaylist(radar.id)
                            }
                        }
                        .buttonStyle(.interactiveCard)
                    }
                }
            }

            if !model.toplists.isEmpty {
                Shelf(title: "排行榜", seeAll: nil, rowHeight: Theme.Layout.compactCoverShelfHeight) {
                    ForEach(model.toplists) { toplist in
                        NavigationLink(value: Destination.playlist(toplist.id)) {
                            toplistCard(toplist)
                        }
                        .buttonStyle(.interactiveCard)
                    }
                }
            }

            if Self.showsNewAlbums, !model.newAlbums.isEmpty {
                Shelf(title: "新碟上架", rowHeight: Theme.Layout.coverShelfHeight) {
                    ForEach(model.newAlbums) { album in
                        albumCard(album)
                    }
                }
            }

            if !model.followedArtistReleases.isEmpty {
                Shelf(title: "关注歌手的新作", rowHeight: Theme.Layout.coverShelfHeight) {
                    ForEach(model.followedArtistReleases) { album in
                        albumCard(album)
                    }
                }
            }

            PlayerClearanceSpacer()
        }
        .padding(.vertical, Theme.Layout.contentInset - 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Feature cards

    private var featureCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Layout.shelfSpacing) {
                Color.clear.frame(
                    width: max(0, Theme.Layout.contentInset - Theme.Layout.shelfSpacing),
                    height: 1
                )
                if account.isLoggedIn {
                    NavigationLink(value: Destination.daily) {
                        FeatureCard(
                            title: "每日推荐",
                            subtitle: "根据你的口味生成",
                            icon: "calendar",
                            coverURL: model.dailyFirstCover?.resizedImageURL(512),
                            showsDate: true
                        )
                    }
                    .buttonStyle(.interactiveCard)

                    Button {
                        player.startFM()
                    } label: {
                        FeatureCard(
                            title: "私人漫游",
                            subtitle: "从喜欢的歌开始漫游",
                            icon: "wave.3.right.circle.fill",
                            artworkName: "private-roaming",
                            gradient: [Color(red: 0.16, green: 0.20, blue: 0.42),
                                       Color(red: 0.36, green: 0.24, blue: 0.62)]
                        )
                    }
                    .buttonStyle(.interactiveCard)

                    Button {
                        startHeartbeatMode()
                    } label: {
                        FeatureCard(
                            title: "心动模式",
                            subtitle: "你的红心歌曲和相似推荐",
                            icon: "heart.circle.fill",
                            artworkName: "heartbeat-mode",
                            gradient: [Color(red: 0.85, green: 0.19, blue: 0.41),
                                       Color(red: 0.98, green: 0.42, blue: 0.34)]
                        )
                    }
                    .buttonStyle(.interactiveCard)

                    NavigationLink(value: Destination.aiRecommendations) {
                        FeatureCard(
                            title: "AI 猜你喜欢",
                            subtitle: "从红心之外发现新歌",
                            icon: "sparkles",
                            artworkName: "ai-discovery",
                            gradient: [Color(red: 0.35, green: 0.23, blue: 0.78),
                                       Color(red: 0.77, green: 0.25, blue: 0.58)]
                        )
                    }
                    .buttonStyle(.interactiveCard)
                }
                Color.clear.frame(
                    width: max(0, Theme.Layout.contentInset - Theme.Layout.shelfSpacing),
                    height: 1
                )
            }
            .padding(.vertical, 6)
        }
        .compatScrollClipDisabled()
    }

    private func startHeartbeatMode() {
        guard let likedList = account.likedSongsPlaylist else { return }
        Task {
            guard let seed = account.likedTrackIDs.randomElement() else {
                ToastCenter.shared.show(String(localized: "先收藏一些喜欢的歌曲吧"))
                return
            }
            do {
                let tracks = try await NeteaseAPI.intelligenceList(songID: seed, playlistID: likedList.id)
                guard !tracks.isEmpty else {
                    ToastCenter.shared.show(String(localized: "心动模式暂时不可用"))
                    return
                }
                player.play(tracks: tracks, source: .playlist(likedList.id),
                            context: .heartbeat)
                ToastCenter.shared.show(String(localized: "已开启心动模式"))
            } catch {
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    // MARK: - Cards

    private func playlistCard(_ playlist: PlaylistSummary) -> some View {
        #if os(iOS)
        let subtitle: String? = nil
        #else
        let subtitle = playlist.copywriter
        #endif
        return NavigationLink(value: Destination.playlist(playlist.id)) {
            CoverCardBody(
                coverURL: playlist.coverURL?.resizedImageURL(384),
                title: playlist.name,
                subtitle: subtitle,
                playCount: playlist.playCount
            ) {
                playPlaylist(playlist.id)
            }
        }
        .buttonStyle(.interactiveCard)
    }

    private func albumCard(_ album: AlbumSummary) -> some View {
        NavigationLink(value: Destination.album(album.id)) {
            CoverCardBody(
                coverURL: album.picUrl?.resizedImageURL(384),
                title: album.name,
                subtitle: album.artistName
            ) {
                Task {
                    if let detail = try? await NeteaseAPI.album(id: album.id) {
                        player.play(tracks: detail.songs, source: .album(album.id),
                                    context: .album(id: album.id, name: album.name))
                    }
                }
            }
        }
        .buttonStyle(.interactiveCard)
    }

    private func toplistCard(_ toplist: ToplistItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: toplist.coverImgUrl?.resizedImageURL(384))
                    .frame(width: Theme.Layout.cardSize, height: Theme.Layout.cardSize)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous))
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous))
                Text(toplist.updateFrequency ?? "")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(8)
            }
            .frame(width: Theme.Layout.cardSize, height: Theme.Layout.cardSize)
            Text(toplist.name)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: Theme.Layout.cardSize, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func playPlaylist(_ id: Int) {
        Task {
            guard let detail = try? await NeteaseAPI.playlistDetail(id: id) else { return }
            var tracks = detail.playlist.tracks
            if tracks.isEmpty {
                let ids = detail.playlist.trackIds.map(\.id)
                tracks = (try? await NeteaseAPI.songDetails(ids: Array(ids.prefix(500))))?.songs ?? []
            }
            player.play(tracks: tracks, source: .playlist(id),
                        context: .playlist(id: id, name: detail.playlist.name))
        }
    }
}

// MARK: - Feature card

struct FeatureCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    var coverURL: URL?
    var artworkName: String?
    var gradient: [Color] = [Color(red: 0.75, green: 0.16, blue: 0.22),
                             Color(red: 0.95, green: 0.35, blue: 0.28)]
    var showsDate = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let artworkName,
               let artwork = FeatureArtwork.image(named: artworkName) {
                Image(platformImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 230, height: 132)
                    .clipped()
                featureArtworkScrim
            } else if let coverURL {
                CachedAsyncImage(url: coverURL)
                    .frame(width: 230, height: 132)
                featureArtworkScrim
            } else {
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.18), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 220)
            }

            VStack(alignment: .leading, spacing: 3) {
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                    if showsDate {
                        Text("\(Calendar.current.component(.day, from: .now))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .offset(y: 3)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .padding(14)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
        .frame(width: 230, height: 132)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        #if os(macOS)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        #endif
        .contentShape(Rectangle())
    }

    private var featureArtworkScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.08), location: 0),
                .init(color: .black.opacity(0.12), location: 0.45),
                .init(color: .black.opacity(0.76), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @MainActor
    enum FeatureArtwork {
        private static var cache: [String: PlatformImage] = [:]

        static func image(named name: String) -> PlatformImage? {
            if let cached = cache[name] {
                return cached
            }

            guard let url = Bundle.module.url(forResource: name, withExtension: "jpg"),
                  let data = try? Data(contentsOf: url),
                  let image = PlatformImage(data: data) else {
                return nil
            }

            cache[name] = image
            return image
        }
    }
}

/// Card body without its own Button wrapper (for use inside NavigationLink).
struct CoverCardBody: View {
    let coverURL: URL?
    let title: String
    var subtitle: String?
    var playCount: Int = 0
    /// Shelves use a fixed card width; grids pass `nil` so artwork follows the
    /// two-column system margin exactly on every iPhone width.
    var size: CGFloat? = Theme.Layout.cardSize
    var onPlay: (() -> Void)?

    @State private var isHovering = false
    @Environment(\.flexibleCardWidth) private var flexibleWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sizedArtwork

            Text(title)
                .font(Theme.Typography.cardTitle)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.Typography.cardSubtitle)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: isFluid ? nil : size, alignment: .leading)
        .frame(maxWidth: isFluid ? .infinity : nil, alignment: .leading)
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
    }

    @ViewBuilder
    private var sizedArtwork: some View {
        if isFluid {
            artwork
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
        } else if let size {
            artwork.frame(width: size, height: size)
        }
    }

    private var isFluid: Bool {
        flexibleWidth || size == nil
    }

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            coverImage
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
    }

    @ViewBuilder
    private var coverImage: some View {
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

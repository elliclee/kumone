import SwiftUI

#if os(iOS)
public struct IOSMainWindow: View {
    @StateObject private var player = PlayerService.shared
    @StateObject private var account = AccountStore.shared
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var toasts = ToastCenter.shared
    @StateObject private var updater = IOSUpdater.shared
    @Namespace private var nowPlayingTransition
    @Environment(\.colorScheme) private var systemColorScheme

    /// The app's intended scheme, read on this ancestor so the search-active
    /// tab environment can't invert it (#31).
    private var resolvedColorScheme: ColorScheme {
        settings.appearance.colorScheme ?? systemColorScheme
    }

    @State private var selectedTab: IOSTab = .home
    @State private var showLogin = false
    @State private var homePath = NavigationPath()
    @State private var explorePath = NavigationPath()
    @State private var fmPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var libraryPath = NavigationPath()

    public init() {}

    public var body: some View {
        presentationRoot
            .environmentObject(player)
            .environmentObject(account)
            .environmentObject(settings)
            .environmentObject(toasts)
            .tint(Theme.accent)
            .preferredColorScheme(settings.appearance.colorScheme)
            .environment(\.openLogin, { showLogin = true })
            .task {
                await account.bootstrap()
                if settings.autoCheckUpdates {
                    IOSUpdater.shared.check(interactive: false)
                }
            }
            .sheet(isPresented: $updater.showSheet) {
                IOSUpdaterSheet()
            }
            .sheet(isPresented: $showLogin) {
                LoginSheet()
                    .environmentObject(account)
                    .environmentObject(toasts)
            }
            .overlay(alignment: .top) {
                if let toast = toasts.current {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .animation(.spring(duration: 0.3), value: toasts.current)
    }

    @ViewBuilder
    private var presentationRoot: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            if #available(iOS 18.0, *) {
                zoomNowPlayingRoot
            } else {
                legacyPresentationRoot
            }
        } else {
            systemNowPlayingRoot
        }
    }

    private var systemNowPlayingRoot: some View {
        appContent
            .fullScreenCover(isPresented: $player.showNowPlaying) {
                systemNowPlayingPresentation
            }
    }

    @available(iOS 18.0, *)
    private var zoomNowPlayingRoot: some View {
        appContent
            .fullScreenCover(isPresented: $player.showNowPlaying) {
                systemNowPlayingPresentation
                    .navigationTransition(
                        .zoom(
                            sourceID: NowPlayingTransitionID.surface,
                            in: nowPlayingTransition
                        )
                    )
            }
    }

    @ViewBuilder
    private var systemNowPlayingPresentation: some View {
        if #available(iOS 16.4, *) {
            nowPlayingPresentation(
                usesSystemInteractiveDismissal: true,
                dismissAnimation: nil
            )
            .presentationBackground(.clear)
        } else {
            nowPlayingPresentation(
                usesSystemInteractiveDismissal: true,
                dismissAnimation: nil
            )
        }
    }

    private var legacyPresentationRoot: some View {
        ZStack {
            appContent

            if player.showNowPlaying {
                // Present full-screen with a bottom slide-up. A previous version
                // used `matchedGeometryEffect(.frame, isSource: false)` here to
                // zoom out of the mini player, but that copies the *source*
                // (mini-bar) frame onto this view — shrinking the whole
                // now-playing page to bar size, so on iOS 16/17 nothing
                // full-screen appeared (#28). The slide-up matches the
                // pull-down-to-dismiss gesture; iOS 18+ still gets the zoom.
                nowPlayingPresentation(
                    usesSystemInteractiveDismissal: false,
                    dismissAnimation: NowPlayingPresentationMetrics.presentationAnimation
                )
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .animation(NowPlayingPresentationMetrics.presentationAnimation, value: player.showNowPlaying)
    }

    @ViewBuilder
    private var appContent: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            MainWindow()
        } else {
            tabInterface
        }
    }

    private func nowPlayingPresentation(
        usesSystemInteractiveDismissal: Bool,
        dismissAnimation: Animation?
    ) -> some View {
        IOSNowPlayingPresentation(
            isPresented: $player.showNowPlaying,
            mode: settings.nowPlayingMode,
            usesSystemInteractiveDismissal: usesSystemInteractiveDismissal,
            dismissAnimation: dismissAnimation
        ) {
            NowPlayingView()
                .environmentObject(player)
                .environmentObject(account)
                .environmentObject(settings)
        }
    }

    @ViewBuilder
    private var tabInterface: some View {
        if #available(iOS 26.0, *) {
            iOS26TabInterface
        } else {
            customTabInterface
        }
    }

    /// Attach the bottom mini-player accessory only when something is playing.
    /// Leaving the modifier on with empty content still renders an empty,
    /// translucent accessory platter above the tab bar when idle (#35), so we
    /// apply it conditionally.
    @available(iOS 26.0, *)
    @ViewBuilder
    private var iOS26TabInterface: some View {
        let base = iOS26TabView.tabBarMinimizeBehavior(.onScrollDown)
        if player.hasCurrentTrack {
            base
                .tabViewBottomAccessory {
                    IOSMiniPlayerAccessory(transitionNamespace: nowPlayingTransition)
                        // Pin the scheme so the search-active tab environment
                        // doesn't flip the bar's text to white (#31).
                        .environment(\.colorScheme, resolvedColorScheme)
                }
                .animation(AppAnimation.standard, value: player.hasCurrentTrack)
        } else {
            base
                .animation(AppAnimation.standard, value: player.hasCurrentTrack)
        }
    }

    @available(iOS 26.0, *)
    private var iOS26TabView: some View {
        TabView(selection: $selectedTab) {
            Tab("推荐", systemImage: "house", value: .home) {
                tabStack(.home) { HomeView() }
            }

            Tab("精选", systemImage: "square.grid.2x2", value: .explore) {
                tabStack(.explore) { ExploreView() }
            }

            Tab("漫游", systemImage: "wave.3.right.circle", value: .fm) {
                tabStack(.fm) { FMView() }
            }

            Tab("我的", systemImage: "person.crop.circle", value: .library) {
                tabStack(.library) { IOSLibraryView(showLogin: $showLogin) }
            }

            Tab(value: .search, role: .search) {
                tabStack(.search) { SearchView(query: "") }
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
        }
    }

    private var customTabInterface: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                page(.home) { tabStack(.home) { HomeView() } }
                page(.explore) { tabStack(.explore) { ExploreView() } }
                page(.fm) { tabStack(.fm) { FMView() } }
                page(.search) { tabStack(.search) { SearchView(query: "") } }
                page(.library) { tabStack(.library) { IOSLibraryView(showLogin: $showLogin) } }
            }

            VStack(spacing: 8) {
                if player.hasCurrentTrack {
                    IOSMiniPlayerBar(presentation: .legacyOverlay)
                        .nowPlayingTransitionSource(in: nowPlayingTransition)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                GlassTabBar(items: Self.tabItems, selection: $selectedTab) { tab in
                    popToRoot(tab)
                }
            }
            .padding(.bottom, 6)
        }
        .animation(AppAnimation.standard, value: player.hasCurrentTrack)
    }

    private func popToRoot(_ tab: IOSTab) {
        switch tab {
        case .home: homePath = NavigationPath()
        case .explore: explorePath = NavigationPath()
        case .fm: fmPath = NavigationPath()
        case .search: searchPath = NavigationPath()
        case .library: libraryPath = NavigationPath()
        }
    }

    @ViewBuilder
    private func tabStack<Content: View>(
        _ tab: IOSTab,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        NavigationStack(path: binding(for: tab)) {
            content().appDestinations()
        }
    }

    @ViewBuilder
    private func page<Content: View>(
        _ tab: IOSTab,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .zIndex(selectedTab == tab ? 1 : 0)
    }

    private func binding(for tab: IOSTab) -> Binding<NavigationPath> {
        switch tab {
        case .home: return $homePath
        case .explore: return $explorePath
        case .fm: return $fmPath
        case .search: return $searchPath
        case .library: return $libraryPath
        }
    }
}

enum IOSTab: Hashable {
    case home, explore, fm, search, library
}

extension IOSMainWindow {
    static let tabItems: [GlassTabBar.Item] = [
        .init(tab: .home, title: "推荐", icon: "house"),
        .init(tab: .explore, title: "精选", icon: "square.grid.2x2"),
        .init(tab: .fm, title: "漫游", icon: "dot.radiowaves.left.and.right"),
        .init(tab: .search, title: "搜索", icon: "magnifyingglass"),
        .init(tab: .library, title: "我的", icon: "person.crop.circle"),
    ]
}

private enum NowPlayingTransitionID {
    static let surface = "now-playing-surface"
}

// MARK: - Mini player bar for iOS

@available(iOS 26.0, *)
private struct IOSMiniPlayerAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let transitionNamespace: Namespace.ID

    var body: some View {
        IOSMiniPlayerBar(presentation: presentation)
            // Match the complete system accessory, never only its artwork.
            .nowPlayingTransitionSource(in: transitionNamespace)
    }

    private var presentation: IOSMiniPlayerBar.Presentation {
        let placementIsInline = placement.map { $0 == .inline }
        return NowPlayingPresentationMetrics.shouldUseInlineMiniPlayerLayout(
            placementIsInline: placementIsInline
        ) ? .inlineAccessory : .bottomAccessory
    }
}

private extension View {
    @ViewBuilder
    func nowPlayingTransitionSource(in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(
                id: NowPlayingTransitionID.surface,
                in: namespace
            )
        } else {
            // Pre-18 presents full-screen with a slide transition (see
            // legacyPresentationRoot); no matched-geometry pairing needed.
            self
        }
    }
}

/// Renders mini-player content inside either a system-owned tab accessory or
/// the material-backed compatibility overlay used before iOS 26.
///
/// Do not add a background for `bottomAccessory` or `inlineAccessory`: the
/// tab view owns their Liquid Glass surface and adding another material creates
/// a visibly nested card.
struct IOSMiniPlayerBar: View {
    enum Presentation {
        case bottomAccessory
        case inlineAccessory
        case legacyOverlay

        var isInline: Bool { self == .inlineAccessory }
        var drawsBackground: Bool { self == .legacyOverlay }
        var showsArtist: Bool { self == .legacyOverlay }
    }

    @EnvironmentObject private var player: PlayerService
    let presentation: Presentation

    var body: some View {
        playerBarSurface
            .simultaneousGesture(expandGesture)
    }

    @ViewBuilder
    private var playerBarSurface: some View {
        if presentation.drawsBackground {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 4) {
            Button(action: showNowPlaying) {
                trackSummary
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nowPlayingAccessibilityLabel)
            .accessibilityHint("打开正在播放")

            if presentation.drawsBackground {
                Button(action: player.previous) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .disabled(player.isFMMode)
                .opacity(player.isFMMode ? 0.35 : 1)
                .accessibilityLabel("上一首")
            }

            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            if !presentation.isInline {
                Button(action: player.next) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("下一首")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private var trackSummary: some View {
        HStack(alignment: .center, spacing: 10) {
            CachedAsyncImage(url: player.currentTrack?.album.picUrl?.resizedImageURL(128))
                .frame(
                    width: artworkSize,
                    height: artworkSize
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .shadow(
                    color: presentation.drawsBackground ? .black.opacity(0.15) : .clear,
                    radius: 4,
                    y: 1
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(player.currentTrack?.name ?? "")
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if presentation.showsArtist {
                    Text(player.currentTrack?.artistNames ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var artworkSize: CGFloat {
        presentation.isInline ? 28 : 40
    }

    private var titleFont: Font {
        presentation.isInline ? .caption.weight(.semibold) : .subheadline
    }

    private var nowPlayingAccessibilityLabel: String {
        let title = player.currentTrack?.name ?? String(localized: "正在播放")
        guard let artist = player.currentTrack?.artistNames, !artist.isEmpty else {
            return title
        }
        return "\(title)，\(artist)"
    }

    private var expandGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard NowPlayingPresentationMetrics.shouldExpandFromMiniPlayer(
                    translation: value.translation.height,
                    predictedTranslation: value.predictedEndTranslation.height
                ) else { return }
                showNowPlaying()
            }
    }

    private func showNowPlaying() {
        if #available(iOS 18.0, *) {
            player.showNowPlaying = true
        } else {
            withAnimation(NowPlayingPresentationMetrics.presentationAnimation) {
                player.showNowPlaying = true
            }
        }
    }
}

// MARK: - iOS Library View

struct IOSLibraryView: View {
    @Binding var showLogin: Bool
    @EnvironmentObject private var account: AccountStore
    @State private var showSettings = false
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        List {
            if let profile = account.profile {
                profileRow(profile)
                    .listRowInsets(
                        EdgeInsets(
                            top: 4,
                            leading: Theme.Layout.contentInset,
                            bottom: 12,
                            trailing: Theme.Layout.contentInset
                        )
                    )
                    .listRowSeparator(.hidden)
            }

            if account.hasAuthCookie {
                if let liked = account.likedSongsPlaylist {
                    destinationRow(
                        title: "我喜欢的音乐",
                        icon: "heart.fill",
                        destination: .playlist(liked.id)
                    )
                }
                destinationRow(title: "每日推荐", icon: "calendar", destination: .daily)
                destinationRow(title: "最近播放", icon: "clock.fill", destination: .recents)
                destinationRow(title: "我的收藏", icon: "star.fill", destination: .collections)
                destinationRow(title: "音乐云盘", icon: "icloud.fill", destination: .cloud)
                    .listRowSeparator(.hidden, edges: .bottom)

                if !account.createdPlaylists.isEmpty {
                    playlistHeader(title: "创建的歌单", showsAddButton: true)
                        .listRowInsets(
                            EdgeInsets(
                                top: 16,
                                leading: Theme.Layout.contentInset,
                                bottom: 4,
                                trailing: Theme.Layout.contentInset
                            )
                        )
                        .listRowSeparator(.hidden)

                    ForEach(account.createdPlaylists) { playlist in
                        NavigationLink(value: Destination.playlist(playlist.id)) {
                            playlistRow(playlist)
                        }
                        .listRowInsets(playlistInsets)
                    }
                }

                if !account.subscribedPlaylists.isEmpty {
                    playlistHeader(title: "收藏的歌单", showsAddButton: false)
                        .listRowInsets(
                            EdgeInsets(
                                top: 16,
                                leading: Theme.Layout.contentInset,
                                bottom: 4,
                                trailing: Theme.Layout.contentInset
                            )
                        )
                        .listRowSeparator(.hidden)

                    ForEach(account.subscribedPlaylists) { playlist in
                        NavigationLink(value: Destination.playlist(playlist.id)) {
                            playlistRow(playlist)
                        }
                        .listRowInsets(playlistInsets)
                    }
                }
            } else {
                signedOutState
                    .frame(maxWidth: .infinity, minHeight: 480)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, Theme.Layout.minimumTouchTarget)
        .navigationTitle("我的")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("设置")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                showSettings = false
                            }
                        }
                    }
            }
        }
        .alert("新建歌单", isPresented: $showNewPlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("创建") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                newPlaylistName = ""
                guard !name.isEmpty else { return }
                Task {
                    do {
                        try await NeteaseAPI.createPlaylist(name: name, isPrivate: false)
                        await account.refreshLibrary()
                        ToastCenter.shared.show(String(localized: "歌单已创建"))
                    } catch {
                        ToastCenter.shared.show(error.localizedDescription)
                    }
                }
            }
            Button("取消", role: .cancel) { newPlaylistName = "" }
        }
    }

    private var playlistInsets: EdgeInsets {
        EdgeInsets(
            top: 4,
            leading: Theme.Layout.contentInset,
            bottom: 4,
            trailing: Theme.Layout.contentInset
        )
    }

    private func profileRow(_ profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: profile.avatarUrl?.resizedImageURL(128))
                .frame(width: 48, height: 48)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.nickname)
                        .font(.headline)
                        .lineLimit(1)
                    if profile.vipType > 0 {
                        VIPBadge()
                    }
                }
                if let signature = profile.signature, !signature.isEmpty {
                    Text(signature)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
    }

    private func destinationRow(
        title: LocalizedStringKey,
        icon: String,
        destination: Destination
    ) -> some View {
        NavigationLink(value: destination) {
            LibraryDestinationRow(title: title, icon: icon)
        }
        .listRowInsets(
            EdgeInsets(
                top: 0,
                leading: Theme.Layout.contentInset,
                bottom: 0,
                trailing: Theme.Layout.contentInset
            )
        )
    }

    private func playlistRow(_ playlist: PlaylistSummary) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: playlist.coverURL?.resizedImageURL(96), animated: false)
                .frame(width: 48, height: 48)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: Theme.Radius.small,
                        style: .continuous
                    )
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(playlist.trackCount) 首")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 52)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 60 }
    }

    @ViewBuilder
    private var signedOutState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label("登录网易云音乐", systemImage: "person.crop.circle")
            } description: {
                Text("同步我喜欢的音乐、歌单与每日推荐")
            } actions: {
                Button("登录") {
                    showLogin = true
                }
                .controlSize(.large)
                .appProminentButtonStyle()
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("登录网易云音乐")
                    .font(.title3.weight(.semibold))
                Text("同步我喜欢的音乐、歌单与每日推荐")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("登录") {
                    showLogin = true
                }
                .controlSize(.large)
                .appProminentButtonStyle()
            }
        }
    }

    private func playlistHeader(
        title: LocalizedStringKey,
        showsAddButton: Bool
    ) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(.primary)
            Spacer()
            if showsAddButton {
                Button {
                    showNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(
                            width: Theme.Layout.minimumTouchTarget,
                            height: Theme.Layout.minimumTouchTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("新建歌单")
            }
        }
        .frame(minHeight: Theme.Layout.minimumTouchTarget)
    }
}

private struct LibraryDestinationRow: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 40 }
    }
}
#endif

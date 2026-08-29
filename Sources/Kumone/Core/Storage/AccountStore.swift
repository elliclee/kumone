import Foundation

/// Login state and the user's library: profile, liked track IDs, playlists.
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published var profile: UserProfile?
    @Published var likedTrackIDs: Set<Int> = []
    @Published var userPlaylists: [PlaylistSummary] = []
    @Published var likedAlbums: [AlbumSummary] = []
    @Published var likedArtists: [ArtistSummary] = []
    @Published var isBootstrapped = false

    var isLoggedIn: Bool { hasAuthCookie && profile != nil }
    var hasAuthCookie: Bool {
        #if DEBUG
        if isUITestAuthenticatedPreview { return true }
        #endif
        return NeteaseClient.shared.isLoggedIn
    }
    var vipType: Int { profile?.vipType ?? 0 }

    var likedSongsPlaylist: PlaylistSummary? {
        userPlaylists.first(where: \.isLikedSongsList) ?? userPlaylists.first
    }

    var createdPlaylists: [PlaylistSummary] {
        guard let uid = profile?.userId else { return [] }
        return userPlaylists.filter { $0.creator?.userId == uid && !$0.isLikedSongsList }
    }

    var subscribedPlaylists: [PlaylistSummary] {
        guard let uid = profile?.userId else { return [] }
        return userPlaylists.filter { $0.creator?.userId != uid }
    }

    private init() {}

    /// Called at launch and after login succeeds.
    func bootstrap() async {
        defer { isBootstrapped = true }
        #if DEBUG
        if isUITestAuthenticatedPreview {
            loadUITestAuthenticatedPreview()
            return
        }
        #endif
        guard hasAuthCookie else { return }
        refreshCookieIfNeeded()
        do {
            profile = try await NeteaseAPI.userAccount()
        } catch {
            return
        }
        await refreshLibrary()
    }

    func refreshLibrary() async {
        guard let uid = profile?.userId else { return }
        async let playlists = try? NeteaseAPI.userPlaylists(uid: uid)
        async let liked = try? NeteaseAPI.likedTrackIDs(uid: uid)
        userPlaylists = await playlists ?? userPlaylists
        if let ids = await liked { likedTrackIDs = Set(ids) }
    }

    func refreshSublists() async {
        async let albums = try? NeteaseAPI.likedAlbums()
        async let artists = try? NeteaseAPI.likedArtists()
        likedAlbums = await albums ?? likedAlbums
        likedArtists = await artists ?? likedArtists
    }

    func isLiked(_ trackID: Int) -> Bool {
        likedTrackIDs.contains(trackID)
    }

    func toggleLike(trackID: Int) async {
        guard isLoggedIn else {
            ToastCenter.shared.show(String(localized: "登录后即可收藏歌曲"))
            return
        }
        let like = !likedTrackIDs.contains(trackID)
        // Optimistic update
        if like { likedTrackIDs.insert(trackID) } else { likedTrackIDs.remove(trackID) }
        do {
            try await NeteaseAPI.likeTrack(id: trackID, like: like)
        } catch {
            if like { likedTrackIDs.remove(trackID) } else { likedTrackIDs.insert(trackID) }
            ToastCenter.shared.show(error.localizedDescription)
        }
        NowPlayingManager.shared.refreshLikeState()
    }

    func logout() async {
        await NeteaseAPI.logout()
        profile = nil
        likedTrackIDs = []
        userPlaylists = []
        likedAlbums = []
        likedArtists = []
    }

    /// Refresh the login cookie at most once per calendar day.
    private func refreshCookieIfNeeded() {
        let key = "auth.lastCookieRefresh"
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: key) < today else { return }
        UserDefaults.standard.set(today, forKey: key)
        Task { await NeteaseAPI.refreshLogin() }
    }

    #if DEBUG
    private var isUITestAuthenticatedPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-authenticated")
    }

    /// Deterministic data for screenshot coverage of the signed-in iPhone UI.
    /// It is compiled only in Debug and never touches the real cookie jar.
    private func loadUITestAuthenticatedPreview() {
        let decoder = JSONDecoder()
        let profileJSON = #"{"userId":1001,"nickname":"RANDOMFLOW","signature":"👋","vipType":11}"#
        let playlistsJSON = #"""
        [
            {"id":1,"name":"我喜欢的音乐","trackCount":128,"specialType":5,"creator":{"userId":1001,"nickname":"RANDOMFLOW"}},
            {"id":2,"name":"RANDOMFLOW 的 2025 年度歌单","trackCount":10,"creator":{"userId":1001,"nickname":"RANDOMFLOW"}},
            {"id":3,"name":"夜晚循环","trackCount":36,"creator":{"userId":1001,"nickname":"RANDOMFLOW"}},
            {"id":4,"name":"收藏的独立音乐","trackCount":52,"subscribed":true,"creator":{"userId":2002,"nickname":"Music Lover"}}
        ]
        """#

        profile = try? decoder.decode(UserProfile.self, from: Data(profileJSON.utf8))
        userPlaylists = (try? decoder.decode([PlaylistSummary].self, from: Data(playlistsJSON.utf8))) ?? []
    }
    #endif
}

// MARK: - Toasts

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published var current: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String) {
        current = Toast(message: message)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            current = nil
        }
    }
}

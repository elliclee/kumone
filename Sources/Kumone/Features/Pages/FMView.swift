import SwiftUI

/// 私人漫游 — immersive personal FM page.
struct FMView: View {
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var account: AccountStore
    @Environment(\.openLogin) private var openLogin
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            backdrop
            if account.hasAuthCookie {
                content
            } else {
                loginPrompt
            }
        }
        .navigationTitle("漫游")
        .compatHiddenToolbarBackground()
    }

    private var track: Track? {
        player.isFMMode ? player.currentTrack : nil
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            Platform.windowBackgroundColor
            if let cover = track?.album.picUrl?.resizedImageURL(384) {
                CachedAsyncImage(url: cover)
                    .scaledToFill()
                    .blur(radius: 80)
                    .opacity(colorScheme == .dark ? 0.45 : 0.3)
                    .saturation(1.4)
            }
            LinearGradient(
                colors: [.clear, Platform.windowBackgroundColor.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .animation(AppAnimation.smooth, value: track?.id)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if player.isFMMode {
            iosActiveContent
        } else {
            iosIdleState
        }
        #else
        desktopContent
        #endif
    }

    #if os(iOS)
    private var iosActiveContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                activeArtwork

                trackMetadata

                controls
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var iosIdleState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label("私人漫游", systemImage: "wave.3.right.circle")
            } description: {
                Text("根据你的口味持续推荐音乐")
            } actions: {
                startFMButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "wave.3.right.circle")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("私人漫游")
                    .font(.title2.bold())
                Text("根据你的口味持续推荐音乐")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                startFMButton
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Theme.Layout.contentInset)
        }
    }

    private var activeArtwork: some View {
        ZStack {
            if let cover = track?.album.picUrl?.resizedImageURL(768) {
                CachedAsyncImage(url: cover)
                    .frame(width: 300, height: 300)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.large,
                            style: .continuous
                        )
                    )
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 300, height: 300)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .scaleEffect(player.isPlaying && !reduceMotion ? 1 : 0.96)
        .animation(reduceMotion ? nil : AppAnimation.smooth, value: player.isPlaying)
        .accessibilityHidden(true)
    }

    private var trackMetadata: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(track?.name ?? String(localized: "私人漫游"))
                    .font(.title2.bold())
                    .lineLimit(1)
                if track?.fee == 1 {
                    VIPBadge()
                }
            }
            Text(track?.artistNames ?? String(localized: "正在为你选歌"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: 360)
    }

    @ViewBuilder
    private var startFMButton: some View {
        Button {
            player.startFM()
        } label: {
            Label("开始漫游", systemImage: "wave.3.right")
                .font(.headline)
        }
        .controlSize(.large)
        .appProminentButtonStyle()
    }
    #endif

    #if os(macOS)
    private var desktopContent: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                if let cover = track?.album.picUrl?.resizedImageURL(768) {
                    CachedAsyncImage(url: cover)
                        .frame(width: 300, height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.quaternary.opacity(0.4))
                        .frame(width: 300, height: 300)
                        .overlay(
                            Image(systemName: "wave.3.right.circle")
                                .font(.system(size: 56, weight: .light))
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            .scaleEffect(player.isPlaying && player.isFMMode ? 1 : 0.94)
            .animation(AppAnimation.bouncy, value: player.isPlaying && player.isFMMode)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(track?.name ?? String(localized: "私人漫游"))
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                    if track?.fee == 1 {
                        VIPBadge()
                    }
                }
                Text(track?.artistNames ?? String(localized: "根据你的口味漫游好音乐"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 420)

            if player.isFMMode {
                controls
            } else {
                Button {
                    player.startFM()
                } label: {
                    Label("开始漫游", systemImage: "wave.3.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Theme.accentGradient, in: Capsule())
                        .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 3)
                }
                .buttonStyle(.pressable)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    #endif

    @ViewBuilder
    private var controls: some View {
        #if os(iOS)
        HStack(spacing: 24) {
            Button {
                player.fmTrash()
            } label: {
                Image(systemName: "trash")
                    .font(.title3.weight(.medium))
                    .frame(
                        width: Theme.Layout.minimumTouchTarget,
                        height: Theme.Layout.minimumTouchTarget
                    )
            }
            .buttonStyle(.pressable)
            .foregroundStyle(.secondary)
            .accessibilityLabel("不喜欢，换一首")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .contentTransition(.opacity)
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .foregroundStyle(.primary)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Button {
                player.fmNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3.weight(.medium))
                    .frame(
                        width: Theme.Layout.minimumTouchTarget,
                        height: Theme.Layout.minimumTouchTarget
                    )
            }
            .buttonStyle(.pressable)
            .foregroundStyle(.secondary)
            .accessibilityLabel("下一首")

            if let track {
                LikeButton(trackID: track.id, size: 18)
                    .frame(
                        width: Theme.Layout.minimumTouchTarget,
                        height: Theme.Layout.minimumTouchTarget
                    )
            }
        }
        #else
        HStack(spacing: 26) {
            Button {
                player.fmTrash()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.pressable)
            .help("不喜欢，换一首")

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 4)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                }
            }
            .buttonStyle(.pressable)

            Button {
                player.fmNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.pressable)
            .help("下一首")

            if let track {
                LikeButton(trackID: track.id, size: 16)
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.06), in: Circle())
            }
        }
        #endif
    }

    @ViewBuilder
    private var loginPrompt: some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label("登录后开启私人漫游", systemImage: "person.crop.circle")
            } description: {
                Text("网易云会根据你的听歌口味推荐音乐")
            } actions: {
                loginButton
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("登录后开启私人漫游")
                    .font(.title2.bold())
                Text("网易云会根据你的听歌口味推荐音乐")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                loginButton
                    .padding(.top, 4)
            }
        }
        #else
        VStack(spacing: 16) {
            Image(systemName: "wave.3.right.circle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tertiary)
            Text("登录后开启私人漫游")
                .font(.headline)
            Text("网易云会根据你的听歌口味推荐音乐")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("登录") { openLogin() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var loginButton: some View {
        Button("登录") { openLogin() }
            .controlSize(.large)
            .appProminentButtonStyle()
    }
    #endif
}

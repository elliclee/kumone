import SwiftUI

@MainActor
final class AIRecommendationsViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded(AIRecommendationResult)
        case error(String)
    }

    @Published var state: State = .idle
    @Published var mood = ""

    func generate(likedTrackIDs: Set<Int>) async {
        guard !isLoading else { return }
        state = .loading
        do {
            state = .loaded(try await AIRecommendationService.generate(
                likedTrackIDs: likedTrackIDs,
                mood: mood
            ))
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }
}

struct AIRecommendationsView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var player: PlayerService
    @Environment(\.openLogin) private var openLogin
    @StateObject private var model = AIRecommendationsViewModel()
    @State private var hasAPIKey = DeepSeekCredentialStore.isConfigured

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                hero
                content
                PlayerClearanceSpacer()
            }
            .padding(Theme.Layout.contentInset)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Kumo 猜你喜欢")
        .onAppear {
            hasAPIKey = DeepSeekCredentialStore.isConfigured
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Label {
                    Text("根据你的红心歌曲生成推荐")
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.accent)
                }
                .font(.headline)

                Text("Kumo 只会将歌名和歌手发送给 AI 推荐服务，并匹配网易云曲库。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tertiary)

                TextField("描述此刻想听的音乐（可选）", text: $model.mood)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .disabled(model.isLoading)

                if !model.mood.isEmpty, !model.isLoading {
                    Button {
                        model.mood = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .minimumInteractiveSize()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除听歌描述")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: Theme.Layout.minimumTouchTarget)
            .background(
                Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if !account.isLoggedIn {
            EmptyStateView(icon: "person.crop.circle.badge.exclamationmark", title: "登录后才能分析你的红心歌曲")
                .frame(minHeight: 280)
            Button("登录网易云音乐") { openLogin() }
                .buttonStyle(.primaryAction)
                .frame(maxWidth: .infinity)
        } else if !hasAPIKey {
            setupCard
        } else if account.likedTrackIDs.count < 3 {
            EmptyStateView(icon: "heart", title: "至少收藏 3 首歌曲后再来试试")
                .frame(minHeight: 280)
        } else {
            switch model.state {
            case .idle:
                generatePrompt
            case .loading:
                loadingState
            case .error(let message):
                errorState(message)
            case .loaded(let result):
                resultView(result)
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("配置 AI 推荐")
                .font(.headline)
            Text("服务密钥会保存在系统钥匙串中，不会发送给网易云音乐。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DeepSeekCredentialEditor { configured in
                hasAPIKey = configured
            }
        }
        .padding(.top, 4)
    }

    private var generatePrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            Text("将随机选取最多 40 首红心歌曲分析")
                .font(.headline)
            Text("每次生成都会调用一次 AI 推荐服务，并可能产生少量费用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            generateButton(title: "生成我的推荐")
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("AI 正在寻找你可能喜欢的歌…")
                .font(.headline)
            Text("生成推荐并匹配曲库通常需要十几秒")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            ErrorStateView(message: message) {
                Task { await model.generate(likedTrackIDs: account.likedTrackIDs) }
            }
            Button("重新配置服务密钥") {
                do {
                    try DeepSeekCredentialStore.delete()
                    hasAPIKey = false
                    model.state = .idle
                } catch {
                    ToastCenter.shared.show(error.localizedDescription)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .minimumInteractiveSize()
        }
        .frame(minHeight: 300)
    }

    private func resultView(_ result: AIRecommendationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("AI 的口味观察", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(result.summary)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack {
                Text("为你推荐")
                    .font(.title3.weight(.semibold))
                Text("\(result.tracks.count) 首")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    player.play(tracks: result.tracks.map(\.track), source: .none)
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .minimumInteractiveSize()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                Button {
                    Task { await model.generate(likedTrackIDs: account.likedTrackIDs) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .frame(width: Theme.Layout.minimumTouchTarget,
                       height: Theme.Layout.minimumTouchTarget)
                .accessibilityLabel("刷新推荐")
            }

            LazyVStack(spacing: 4) {
                ForEach(Array(result.tracks.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 0) {
                        TrackRow(track: item.track, index: index + 1) {
                            player.play(
                                tracks: result.tracks.map(\.track),
                                source: .none,
                                startAt: item.track
                            )
                        }
                        Text(item.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 76)
                            .padding(.trailing, 12)
                            .padding(.bottom, 8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func generateButton(title: LocalizedStringKey) -> some View {
        Button {
            Task { await model.generate(likedTrackIDs: account.likedTrackIDs) }
        } label: {
            Label(title, systemImage: "sparkles")
        }
        .buttonStyle(.primaryAction)
    }
}

struct DeepSeekCredentialEditor: View {
    var onChange: (Bool) -> Void = { _ in }

    @State private var draft = ""
    @State private var configured = DeepSeekCredentialStore.isConfigured

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField(
                configured ? "已配置，输入新密钥可替换" : "输入服务密钥",
                text: $draft
            )
            .textContentType(.password)
            .disableAutocorrection(true)

            HStack {
                if configured {
                    Label("已安全保存", systemImage: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if configured {
                    Button("移除", role: .destructive) { remove() }
                }
                Button(configured ? "替换" : "保存") { save() }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        do {
            try DeepSeekCredentialStore.save(draft)
            draft = ""
            configured = true
            onChange(true)
            ToastCenter.shared.show(String(localized: "AI 推荐服务密钥已保存"))
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    private func remove() {
        do {
            try DeepSeekCredentialStore.delete()
            draft = ""
            configured = false
            onChange(false)
            ToastCenter.shared.show(String(localized: "AI 推荐服务密钥已移除"))
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }
}

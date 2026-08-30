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
        .navigationTitle("AI 猜你喜欢")
        .onAppear {
            hasAPIKey = DeepSeekCredentialStore.isConfigured
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.35, green: 0.23, blue: 0.78),
                                     Color(red: 0.77, green: 0.25, blue: 0.58)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("让 AI 从红心歌曲里读懂你的口味")
                        .font(.title3.weight(.semibold))
                    Text("只发送歌名和歌手，推荐结果会匹配到网易云曲库")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("此刻想听什么？例如：适合雨夜通勤（可选）", text: $model.mood)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isLoading)
        }
        .padding(18)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if !account.isLoggedIn {
            EmptyStateView(icon: "person.crop.circle.badge.exclamationmark", title: "登录后才能分析你的红心歌曲")
                .frame(minHeight: 280)
            Button("登录网易云音乐") { openLogin() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
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
            Text("连接 DeepSeek")
                .font(.headline)
            Text("使用你自己的 API Key。Key 会保存在系统钥匙串中，不会发送给网易云音乐。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DeepSeekCredentialEditor { configured in
                hasAPIKey = configured
            }
        }
        .padding(18)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var generatePrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            Text("将随机选取最多 40 首红心歌曲分析")
                .font(.headline)
            Text("每次生成都会调用一次 DeepSeek API，并可能产生少量费用。")
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
            Button("重新配置 API Key") {
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
        }
        .frame(minHeight: 300)
    }

    private func resultView(_ result: AIRecommendationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI 的口味观察")
                    .font(.headline)
                Text(result.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                Button {
                    Task { await model.generate(likedTrackIDs: account.likedTrackIDs) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
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
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }
}

struct DeepSeekCredentialEditor: View {
    var onChange: (Bool) -> Void = { _ in }

    @State private var draft = ""
    @State private var configured = DeepSeekCredentialStore.isConfigured

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField(
                configured ? "已配置，输入新 Key 可替换" : "sk-…",
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
            ToastCenter.shared.show(String(localized: "DeepSeek API Key 已保存"))
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
            ToastCenter.shared.show(String(localized: "DeepSeek API Key 已移除"))
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }
}

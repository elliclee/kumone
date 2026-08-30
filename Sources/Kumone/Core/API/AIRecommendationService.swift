import Foundation

struct AIRecommendedTrack: Identifiable, Hashable {
    let track: Track
    let reason: String

    var id: Int { track.id }
}

struct AIRecommendationResult: Hashable {
    let summary: String
    let tracks: [AIRecommendedTrack]
}

enum AIRecommendationServiceError: LocalizedError {
    case notEnoughTasteData
    case noCatalogMatches

    var errorDescription: String? {
        switch self {
        case .notEnoughTasteData:
            return String(localized: "至少收藏 3 首歌曲后，AI 才能猜出你的口味")
        case .noCatalogMatches:
            return String(localized: "AI 的推荐暂时没有匹配到网易云曲库，请再试一次")
        }
    }
}

enum AIRecommendationService {
    static func generate(likedTrackIDs: Set<Int>, mood: String?) async throws -> AIRecommendationResult {
        guard likedTrackIDs.count >= 3 else {
            throw AIRecommendationServiceError.notEnoughTasteData
        }
        let seedIDs = Array(likedTrackIDs.shuffled().prefix(40))
        let seedTracks = try await NeteaseAPI.songDetails(ids: seedIDs).songs
        guard seedTracks.count >= 3 else {
            throw AIRecommendationServiceError.notEnoughTasteData
        }

        let payload = try await DeepSeekClient.shared.recommend(from: seedTracks, mood: mood)
        let matches = await resolve(Array(payload.recommendations.prefix(24)), excluding: likedTrackIDs)
        guard !matches.isEmpty else { throw AIRecommendationServiceError.noCatalogMatches }
        return AIRecommendationResult(summary: payload.summary, tracks: Array(matches.prefix(15)))
    }

    static func resolve(
        _ candidates: [DeepSeekSongCandidate],
        excluding excludedIDs: Set<Int>
    ) async -> [AIRecommendedTrack] {
        await withTaskGroup(of: (Int, AIRecommendedTrack?).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let query = "\(candidate.title) \(candidate.artist)"
                    guard let songs = try? await NeteaseAPI.search(query, type: .songs, limit: 8).songs,
                          let match = bestMatch(
                            for: candidate,
                            in: songs.filter { !excludedIDs.contains($0.id) }
                          ) else {
                        return (index, nil)
                    }
                    return (index, AIRecommendedTrack(track: match, reason: candidate.reason))
                }
            }
            var indexed: [(Int, AIRecommendedTrack)] = []
            for await (index, recommendation) in group {
                if let recommendation { indexed.append((index, recommendation)) }
            }
            var seen = Set<Int>()
            return indexed.sorted { $0.0 < $1.0 }
                .map(\.1)
                .filter { seen.insert($0.id).inserted }
        }
    }

    static func bestMatch(for candidate: DeepSeekSongCandidate, in tracks: [Track]) -> Track? {
        tracks.compactMap { track -> (Track, Int)? in
            let score = matchScore(candidate: candidate, track: track)
            return score >= 70 ? (track, score) : nil
        }
        .max { $0.1 < $1.1 }?.0
    }

    static func matchScore(candidate: DeepSeekSongCandidate, track: Track) -> Int {
        let wantedTitle = normalized(candidate.title)
        let titles = ([track.name] + track.alias + track.transNames).map(normalized)
        let titleScore: Int
        if titles.contains(wantedTitle) {
            titleScore = 60
        } else if titles.contains(where: { containsEither($0, wantedTitle) }) {
            titleScore = 40
        } else {
            return 0
        }

        let wantedArtist = normalized(candidate.artist)
        let artistNames = track.artists.map { normalized($0.name) }
        let joinedArtists = normalized(track.artistNames)
        let artistScore: Int
        if artistNames.contains(wantedArtist) || joinedArtists == wantedArtist {
            artistScore = 40
        } else if artistNames.contains(where: { containsEither($0, wantedArtist) })
                    || containsEither(joinedArtists, wantedArtist) {
            artistScore = 30
        } else {
            artistScore = 0
        }
        return titleScore + artistScore
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func containsEither(_ lhs: String, _ rhs: String) -> Bool {
        guard min(lhs.count, rhs.count) >= 3 else { return false }
        return lhs.contains(rhs) || rhs.contains(lhs)
    }
}

import Testing
import Foundation
@testable import KumoneCore

@Suite("AI Recommendation Tests")
struct AIRecommendationTests {
    @Test func normalizationIgnoresCaseWidthAccentsAndPunctuation() {
        #expect(AIRecommendationService.normalized("Ｃａｆé・Night!") == "cafenight")
    }

    @Test func exactTitleAndArtistIsReliableMatch() throws {
        let candidate = DeepSeekSongCandidate(
            title: "夜空中最亮的星",
            artist: "逃跑计划",
            reason: "相似的摇滚情绪"
        )
        let track = try decodeTrack(name: "夜空中最亮的星", artist: "逃跑计划")

        #expect(AIRecommendationService.matchScore(candidate: candidate, track: track) == 100)
        #expect(AIRecommendationService.bestMatch(for: candidate, in: [track])?.id == track.id)
    }

    @Test func sameTitleWithWrongArtistIsRejected() throws {
        let candidate = DeepSeekSongCandidate(title: "后来", artist: "刘若英", reason: "叙事感")
        let unrelatedCover = try decodeTrack(name: "后来", artist: "其他歌手")

        #expect(AIRecommendationService.matchScore(candidate: candidate, track: unrelatedCover) == 60)
        #expect(AIRecommendationService.bestMatch(for: candidate, in: [unrelatedCover]) == nil)
    }

    @Test func aliasCanMatchRecommendedTitle() throws {
        let candidate = DeepSeekSongCandidate(title: "The Brightest Star in the Night Sky", artist: "Escape Plan", reason: "旋律")
        let track = try decodeTrack(
            name: "夜空中最亮的星",
            artist: "Escape Plan",
            aliases: ["The Brightest Star in the Night Sky"]
        )

        #expect(AIRecommendationService.bestMatch(for: candidate, in: [track])?.id == track.id)
    }

    @Test func deepSeekJSONPayloadDecodes() throws {
        let json = """
        {"summary":"偏爱旋律摇滚","recommendations":[{"title":"一万次悲伤","artist":"逃跑计划","reason":"延续明亮而有力量的摇滚旋律"}]}
        """
        let payload = try JSONDecoder().decode(
            DeepSeekRecommendationPayload.self,
            from: Data(json.utf8)
        )

        #expect(payload.summary == "偏爱旋律摇滚")
        #expect(payload.recommendations.first?.title == "一万次悲伤")
    }

    @Test func alternateVersionSharesSeedSignature() throws {
        let seed = try decodeTrack(id: 1, name: "Bloom", artist: "The Paper Kites")
        let alternate = try decodeTrack(id: 2, name: "Bloom", artist: "The Paper Kites")

        #expect(seed.id != alternate.id)
        #expect(!AIRecommendationService.signatures(for: seed).isDisjoint(
            with: AIRecommendationService.signatures(for: alternate)
        ))
    }

    @Test func familiarArtistsAreCapped() throws {
        let firstKnown = try decodeTrack(id: 1, name: "Song A", artist: "Known Artist")
        let secondKnown = try decodeTrack(id: 2, name: "Song B", artist: "Known Artist")
        let discovery = try decodeTrack(id: 3, name: "Song C", artist: "New Artist")
        let recommendations = [firstKnown, secondKnown, discovery].map {
            AIRecommendedTrack(track: $0, reason: "Test")
        }

        let limited = AIRecommendationService.limitKnownArtists(
            recommendations,
            knownArtists: [AIRecommendationService.normalized("Known Artist")],
            limit: 1
        )

        #expect(limited.map(\.id) == [firstKnown.id, discovery.id])
    }

    private func decodeTrack(
        id: Int = 42,
        name: String,
        artist: String,
        aliases: [String] = []
    ) throws -> Track {
        let object: [String: Any] = [
            "id": id,
            "name": name,
            "ar": [["id": 7, "name": artist]],
            "al": ["id": 9, "name": "Test Album", "picUrl": NSNull()],
            "dt": 180_000,
            "alia": aliases,
            "tns": [],
            "fee": 0,
            "mv": 0,
            "no": 1,
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Track.self, from: data)
    }
}

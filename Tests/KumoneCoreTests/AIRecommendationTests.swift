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

    private func decodeTrack(
        name: String,
        artist: String,
        aliases: [String] = []
    ) throws -> Track {
        let object: [String: Any] = [
            "id": 42,
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

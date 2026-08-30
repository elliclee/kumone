import Foundation
import Testing
@testable import KumoneCore

@Suite("Home followed-artist releases")
struct HomeFollowedArtistReleaseTests {
    @Test("sorts newest first, removes duplicates, and drops stale releases")
    func selectsRecentUniqueReleases() throws {
        let newest = try album(id: 30, publishTime: 3_000)
        let middle = try album(id: 20, publishTime: 2_000)
        let stale = try album(id: 10, publishTime: 999)

        let selected = FollowedArtistReleaseSelector.select(
            from: [[middle, stale], [newest, middle]],
            newerThan: 1_000
        )

        #expect(selected.map(\.id) == [30, 20])
    }

    @Test("honors the shelf item limit")
    func limitsReleaseCount() throws {
        let albums = try (1...5).map { id in
            try album(id: id, publishTime: id * 1_000)
        }

        let selected = FollowedArtistReleaseSelector.select(
            from: [albums],
            newerThan: 0,
            limit: 3
        )

        #expect(selected.map(\.id) == [5, 4, 3])
    }

    private func album(id: Int, publishTime: Int) throws -> AlbumSummary {
        let json = """
        {
          "id": \(id),
          "name": "Release \(id)",
          "picUrl": "https://example.com/\(id).jpg",
          "artist": {"name": "Artist \(id)"},
          "publishTime": \(publishTime),
          "size": 8,
          "subType": "专辑",
          "alias": []
        }
        """
        return try JSONDecoder().decode(AlbumSummary.self, from: Data(json.utf8))
    }
}

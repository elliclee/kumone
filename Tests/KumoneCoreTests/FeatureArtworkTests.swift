import Testing
@testable import KumoneCore

@Suite("Feature artwork resources")
@MainActor
struct FeatureArtworkTests {
    @Test func bundledArtworkCanBeDecoded() throws {
        for name in ["private-roaming", "heartbeat-mode", "ai-discovery"] {
            let image = try #require(FeatureCard.FeatureArtwork.image(named: name))
            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    }

    @Test func missingArtworkReturnsNil() {
        #expect(FeatureCard.FeatureArtwork.image(named: "missing-artwork") == nil)
    }
}

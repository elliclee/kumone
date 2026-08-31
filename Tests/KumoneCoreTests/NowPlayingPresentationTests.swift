import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import KumoneCore

@Suite("Now Playing Presentation Tests")
struct NowPlayingPresentationTests {
    @Test func panoramicArtworkUsesMostOfATallPhoneWithoutOverflowing() {
        let phone = CGSize(width: 393, height: 759)
        let height = ImmersivePanoramaMetrics.artworkHeight(for: phone)

        #expect(height == phone.height * ImmersivePanoramaMetrics.artworkHeightRatio)
        #expect(height < phone.height)
    }

    @Test func panoramicArtworkKeepsUsefulHeightOnShortScreens() {
        let shortPhone = CGSize(width: 320, height: 480)
        let tinyViewport = CGSize(width: 240, height: 300)

        #expect(
            ImmersivePanoramaMetrics.artworkHeight(for: shortPhone)
                == ImmersivePanoramaMetrics.minimumArtworkHeight
        )
        #expect(ImmersivePanoramaMetrics.artworkHeight(for: tinyViewport) == tinyViewport.height)
    }

    @Test func panoramaCanvasExtendsThroughBothSafeAreas() {
        let content = CGSize(width: 402, height: 778)
        let insets = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)

        #expect(
            ImmersivePanoramaMetrics.canvasSize(
                contentSize: content,
                safeAreaInsets: insets
            ) == CGSize(width: 402, height: 874)
        )
        #expect(
            ImmersivePanoramaMetrics.canvasOffset(safeAreaInsets: insets)
                == CGSize(width: 0, height: -14)
        )
    }

    @Test func immersiveControlsRespectTheBottomSafeArea() {
        #expect(
            ImmersivePanoramaMetrics.controlsBottomPadding(safeAreaBottom: 34)
                == 34
        )
        #expect(
            ImmersivePanoramaMetrics.controlsBottomPadding(safeAreaBottom: 0)
                == ImmersivePanoramaMetrics.minimumControlsBottomPadding
        )
    }

    @Test func brightArtworkGetsAStrongerTopScrim() throws {
        let bright = try solidImage(red: 0.96, green: 0.96, blue: 0.96)
        let dark = try solidImage(red: 0.08, green: 0.08, blue: 0.08)

        let brightPalette = ArtworkPalette.compute(from: bright)
        let darkPalette = ArtworkPalette.compute(from: dark)

        #expect(brightPalette.topScrimOpacity > darkPalette.topScrimOpacity)
        #expect(brightPalette.topScrimOpacity <= 0.36)
    }

    @Test func vividArtworkKeepsColorWhileProducingADarkSurface() throws {
        let blue = try solidImage(red: 0.08, green: 0.46, blue: 0.92)
        let palette = ArtworkPalette.compute(from: blue)

        #expect(palette.primaryTone.saturation > 0.6)
        #expect(palette.primaryTone.hue > 0.52)
        #expect(palette.primaryTone.hue < 0.65)
        #expect(palette.surfaceTone.brightness <= 0.13)
        #expect(palette.surfaceTone.brightness < palette.secondaryTone.brightness)
    }

    private func solidImage(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) throws -> NSImage {
        let size = 24
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let color = try #require(CGColor(
            colorSpace: colorSpace,
            components: [red, green, blue, 1]
        ))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try #require(context.makeImage())
        return NSImage(cgImage: image, size: NSSize(width: size, height: size))
    }
}

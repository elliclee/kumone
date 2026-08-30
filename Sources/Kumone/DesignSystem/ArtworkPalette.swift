import CoreGraphics
import SwiftUI

struct ArtworkTone: Equatable {
    var hue: CGFloat
    var saturation: CGFloat
    var brightness: CGFloat

    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

/// Roles used by an artwork-driven background. The dominant tone provides
/// ambient color, while the edge tone and surface tone are derived from the
/// bottom of the image so the artwork can dissolve into the controls without
/// an unrelated color appearing at the seam.
struct ArtworkColors: Equatable {
    var primaryTone: ArtworkTone
    var secondaryTone: ArtworkTone
    var surfaceTone: ArtworkTone
    var topScrimOpacity: Double

    var primary: Color { primaryTone.color }
    var secondary: Color { secondaryTone.color }
    var surface: Color { surfaceTone.color }

    static let fallback = ArtworkColors(
        primaryTone: ArtworkTone(hue: 0.66, saturation: 0.12, brightness: 0.2),
        secondaryTone: ArtworkTone(hue: 0.66, saturation: 0.14, brightness: 0.12),
        surfaceTone: ArtworkTone(hue: 0.66, saturation: 0.12, brightness: 0.075),
        topScrimOpacity: 0.18
    )
}

enum ArtworkPalette {
    private static var cache: [String: ArtworkColors] = [:]

    @MainActor
    static func extract(from image: PlatformImage, cacheKey: String) -> ArtworkColors {
        if let cached = cache[cacheKey] {
            return cached
        }
        let colors = compute(from: image)
        if cache.count > 200 { cache.removeAll() }
        cache[cacheKey] = colors
        return colors
    }

    static func compute(from image: PlatformImage) -> ArtworkColors {
        guard let cgImage = image.cgImageRef else { return .fallback }
        let size = 16
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * size
        let bitsPerComponent = 8
        var rawData = [UInt8](repeating: 0, count: size * size * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &rawData,
            width: size,
            height: size,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return .fallback }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var samples: [PixelSample] = []
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * bytesPerPixel
                let r = CGFloat(rawData[offset]) / 255.0
                let g = CGFloat(rawData[offset + 1]) / 255.0
                let blue = CGFloat(rawData[offset + 2]) / 255.0
                let a = CGFloat(rawData[offset + 3]) / 255.0
                guard a > 0.1 else { continue }

                let hsb = hsb(red: r, green: g, blue: blue)
                samples.append(PixelSample(
                    y: y,
                    red: r,
                    green: g,
                    blue: blue,
                    hue: hsb.hue,
                    saturation: hsb.saturation,
                    brightness: hsb.brightness
                ))
            }
        }
        guard !samples.isEmpty else { return .fallback }

        let dominant = dominantTone(in: samples)
        let bottom = bottomEdgeTone(in: samples, sampleSize: size)
        let topLuminance = averageTopLuminance(in: samples, sampleSize: size)

        let preservesNeutralHue = dominant.saturation < 0.04 && bottom.saturation < 0.04
        let dominantHue = preservesNeutralHue ? ArtworkColors.fallback.primaryTone.hue : dominant.hue
        let primarySaturation = clamp(
            max(dominant.saturation * 1.08, bottom.saturation * 0.72),
            minimum: preservesNeutralHue ? 0.06 : 0.12,
            maximum: 0.72
        )
        let primary = ArtworkTone(
            hue: dominantHue,
            saturation: primarySaturation,
            brightness: clamp(
                dominant.brightness * 0.66,
                minimum: 0.28,
                maximum: 0.44
            )
        )

        // A near-gray image edge inherits a restrained amount of the dominant
        // hue instead of collapsing into generic charcoal.
        let edgeHue = bottom.saturation >= 0.1 ? bottom.hue : dominantHue
        let edgeSaturation = clamp(
            max(bottom.saturation * 0.88, primarySaturation * 0.38),
            minimum: 0.1,
            maximum: 0.62
        )
        let secondary = ArtworkTone(
            hue: edgeHue,
            saturation: edgeSaturation,
            brightness: clamp(
                bottom.brightness * 0.42,
                minimum: 0.12,
                maximum: 0.22
            )
        )
        let surface = ArtworkTone(
            hue: edgeHue,
            saturation: clamp(edgeSaturation * 0.78, minimum: 0.08, maximum: 0.46),
            brightness: clamp(
                bottom.brightness * 0.24,
                minimum: 0.065,
                maximum: 0.13
            )
        )
        let topScrimOpacity = Double(clamp(
            0.12 + max(topLuminance - 0.42, 0) * 0.56,
            minimum: 0.12,
            maximum: 0.36
        ))

        return ArtworkColors(
            primaryTone: primary,
            secondaryTone: secondary,
            surfaceTone: surface,
            topScrimOpacity: topScrimOpacity
        )
    }

    private struct PixelSample {
        let y: Int
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat

        var luminance: CGFloat {
            red * 0.2126 + green * 0.7152 + blue * 0.0722
        }
    }

    private static func dominantTone(in samples: [PixelSample]) -> ArtworkTone {
        let binCount = 12
        var binWeights = [CGFloat](repeating: 0, count: binCount)
        for sample in samples {
            let weight = vividnessWeight(for: sample)
            let bin = min(Int(sample.hue * CGFloat(binCount)), binCount - 1)
            binWeights[bin] += weight
        }

        let dominantBin = binWeights.indices.max(by: {
            binWeights[$0] < binWeights[$1]
        }) ?? 0
        let centerHue = (CGFloat(dominantBin) + 0.5) / CGFloat(binCount)

        var sinSum: CGFloat = 0, cosSum: CGFloat = 0, weightSum: CGFloat = 0
        var satSum: CGFloat = 0, brightSum: CGFloat = 0
        for sample in samples {
            guard circularDistance(sample.hue, centerHue) <= 0.125 else { continue }
            let weight = vividnessWeight(for: sample)
            let angle = sample.hue * 2 * .pi
            sinSum += sin(angle) * weight
            cosSum += cos(angle) * weight
            satSum += sample.saturation * weight
            brightSum += sample.brightness * weight
            weightSum += weight
        }

        guard weightSum > 0.001 else {
            let averageBrightness = samples.map(\.brightness).reduce(0, +)
                / CGFloat(samples.count)
            return ArtworkTone(hue: 0.66, saturation: 0.08, brightness: averageBrightness)
        }

        var hue = atan2(sinSum, cosSum) / (2 * .pi)
        if hue < 0 { hue += 1 }
        return ArtworkTone(
            hue: hue,
            saturation: satSum / weightSum,
            brightness: brightSum / weightSum
        )
    }

    private static func bottomEdgeTone(
        in samples: [PixelSample],
        sampleSize: Int
    ) -> ArtworkTone {
        let startRow = Int(CGFloat(sampleSize) * 0.68)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        var weightSum: CGFloat = 0

        for sample in samples where sample.y >= startRow {
            let position = CGFloat(sample.y - startRow + 1)
                / CGFloat(max(sampleSize - startRow, 1))
            let weight = 0.6 + position * 0.4
            red += sample.red * weight
            green += sample.green * weight
            blue += sample.blue * weight
            weightSum += weight
        }

        guard weightSum > 0 else { return .init(hue: 0.66, saturation: 0.1, brightness: 0.15) }
        return hsb(
            red: red / weightSum,
            green: green / weightSum,
            blue: blue / weightSum
        )
    }

    private static func averageTopLuminance(
        in samples: [PixelSample],
        sampleSize: Int
    ) -> CGFloat {
        let endRow = max(Int(CGFloat(sampleSize) * 0.32), 1)
        let top = samples.filter { $0.y < endRow }
        guard !top.isEmpty else { return 0.5 }
        return top.map(\.luminance).reduce(0, +) / CGFloat(top.count)
    }

    private static func vividnessWeight(for sample: PixelSample) -> CGFloat {
        let saturationWeight = max(
            sample.saturation * sample.saturation.squareRoot(),
            0.012
        )
        let brightnessWeight = 0.38 + 0.62 * (1 - abs(sample.brightness - 0.58))
        return saturationWeight * brightnessWeight
    }

    private static func circularDistance(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let direct = abs(lhs - rhs)
        return min(direct, 1 - direct)
    }

    private static func hsb(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) -> ArtworkTone {
        let maximum = max(red, max(green, blue))
        let minimum = min(red, min(green, blue))
        let delta = maximum - minimum
        let saturation = maximum == 0 ? 0 : delta / maximum
        var hue: CGFloat = 0

        if delta > 0.00001 {
            if red == maximum {
                hue = (green - blue) / delta
            } else if green == maximum {
                hue = 2 + (blue - red) / delta
            } else {
                hue = 4 + (red - green) / delta
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        return ArtworkTone(hue: hue, saturation: saturation, brightness: maximum)
    }

    private static func clamp(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

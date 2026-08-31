import SwiftUI

/// Design tokens: color, radius, spacing, layout metrics.
enum Theme {
    /// iOS uses the clearer pink-red associated with Music and system media
    /// controls. macOS keeps Kumo's original, slightly warmer brand red.
    static let accent: Color = {
        #if os(iOS)
        return Color(red: 0.98, green: 0.15, blue: 0.27) // #FA2645
        #else
        return Color(red: 0.925, green: 0.286, blue: 0.286) // #EC4949
        #endif
    }()
    static let accentDeep: Color = {
        #if os(iOS)
        return Color(red: 0.82, green: 0.08, blue: 0.19)
        #else
        return Color(red: 0.788, green: 0.161, blue: 0.161) // #C92929
        #endif
    }()

    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.973, green: 0.357, blue: 0.357), accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    enum Radius {
        static let badge: CGFloat = 4
        static let small: CGFloat = 6
        static let standard: CGFloat = 8
        static let large: CGFloat = 12
        static let panel: CGFloat = 20
    }

    enum Typography {
        static var sectionTitle: Font {
            #if os(iOS)
            return .title2.weight(.bold)
            #else
            return .title2.weight(.semibold)
            #endif
        }

        static var cardTitle: Font {
            #if os(iOS)
            return .subheadline
            #else
            return .system(size: 13, weight: .medium)
            #endif
        }

        static var cardSubtitle: Font {
            #if os(iOS)
            return .footnote
            #else
            return .system(size: 11)
            #endif
        }
    }

    enum Layout {
        /// Aligns feed content with the system navigation margin on iPhone.
        /// macOS keeps the roomier desktop inset.
        static let contentInset: CGFloat = {
            #if os(iOS)
            return 16
            #else
            return 24
            #endif
        }()
        static let minimumTouchTarget: CGFloat = 44
        static let sectionSpacing: CGFloat = {
            #if os(iOS)
            return 24
            #else
            return 34
            #endif
        }()
        static let shelfSpacing: CGFloat = {
            #if os(iOS)
            return 12
            #else
            return 16
            #endif
        }()
        static let gridSpacing: CGFloat = {
            #if os(iOS)
            return 12
            #else
            return 20
            #endif
        }()
        static let cardSize: CGFloat = 160
        /// Row height for a shelf of cover cards: artwork, then up to two lines
        /// of title and one of subtitle.
        static let coverShelfHeight: CGFloat = {
            #if os(iOS)
            return 232
            #else
            return 226
            #endif
        }()
        /// Artwork plus a two-line title, without a subtitle row.
        static let compactCoverShelfHeight: CGFloat = {
            #if os(iOS)
            return 206
            #else
            return coverShelfHeight
            #endif
        }()
        /// Row height for a shelf of artist cards: circular artwork, one name.
        static let artistShelfHeight: CGFloat = 196
        static let sidebarWidth: CGFloat = 220
        static let playerBarHeight: CGFloat = 56
        /// Gap between the floating player bar and the window's bottom edge.
        /// Must match the bar's own `.padding(.bottom,)` in PlayerBar.
        static let playerBarBottomMargin: CGFloat = 10
        /// Bottom inset pages need so scrolled content clears the floating bar.
        static var playerChromeClearance: CGFloat { playerBarHeight + playerBarBottomMargin }
        static let minWindowWidth: CGFloat = 1020
        /// Width the split view's divider occupies between the two columns.
        static let splitDividerWidth: CGFloat = 8
        /// Window minimum while the sidebar is collapsed. The window-wide
        /// minimum is a *content* constraint, so with the sidebar hidden it
        /// lands entirely on the detail column; restoring the sidebar would
        /// then add its width on top and `.contentMinSize` would widen the
        /// window every time the now-playing page is dismissed (#19).
        /// Subtracting the sidebar here keeps the restored total at
        /// `minWindowWidth`.
        static var minWindowWidthSidebarCollapsed: CGFloat {
            minWindowWidth - sidebarWidth - splitDividerWidth
        }
        static let minWindowHeight: CGFloat = 640
        static let defaultWindowWidth: CGFloat = 1200
        static let defaultWindowHeight: CGFloat = 780
    }
}

/// Motion tokens (mirrors kaset's `AppAnimation`).
enum AppAnimation {
    static let quick = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let smooth = Animation.easeInOut(duration: 0.35)
    /// Default state changes on iOS settle without decorative bounce.
    static let spring: Animation = {
        #if os(iOS)
        return .spring(response: 0.32, dampingFraction: 0.9)
        #else
        return .spring(response: 0.35, dampingFraction: 0.7)
        #endif
    }()
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let snappy: Animation = {
        #if os(iOS)
        return .spring(response: 0.25, dampingFraction: 0.9)
        #else
        return .spring(response: 0.25, dampingFraction: 0.8)
        #endif
    }()

    static let staggerDelay = 0.04
    static let maxStaggerDelay = 0.4

    static func stagger(for index: Int) -> Double {
        min(Double(index) * staggerDelay, maxStaggerDelay)
    }
}

extension View {
    /// `scrollClipDisabled` is iOS 17 / macOS 14; older systems clip normally.
    @ViewBuilder
    func compatScrollClipDisabled() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) { scrollClipDisabled() } else { self }
    }

    /// Hides the toolbar background; `toolbarBackgroundVisibility` is
    /// macOS 15+/iOS 18+, so iOS 17 falls back to `toolbarBackground`.
    @ViewBuilder
    func compatHiddenToolbarBackground() -> some View {
        #if os(macOS)
        toolbarBackgroundVisibility(.hidden, for: .automatic)
        #else
        if #available(iOS 18.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .automatic)
        } else {
            toolbarBackground(.hidden, for: .navigationBar)
        }
        #endif
    }

    /// Glass background with a graceful material fallback on macOS 15.
    @ViewBuilder
    func compatGlass(interactive: Bool = false, in shape: some Shape) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #elseif os(iOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

import SwiftUI

/// Cards that scale up on hover, scale down on press, with a soft shadow.
struct InteractiveCardStyle: ButtonStyle {
    var showShadow = true
    var hoverScale: CGFloat = 1.02
    var pressScale: CGFloat = 0.98
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(macOS)
    @State private var isHovering = false
    #endif

    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        configuration.label
            .scaleEffect(configuration.isPressed ? pressScale : (isHovering ? hoverScale : 1.0))
            .shadow(
                color: showShadow && isHovering ? .black.opacity(0.15) : .clear,
                radius: isHovering ? 12 : 0,
                x: 0,
                y: isHovering ? 4 : 0
            )
            .animation(AppAnimation.spring, value: configuration.isPressed)
            .animation(AppAnimation.spring, value: isHovering)
            .onHover { isHovering = $0 }
        #else
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressScale : 1)
            .opacity(configuration.isPressed ? 0.72 : 1.0)
            .animation(reduceMotion ? nil : AppAnimation.quick, value: configuration.isPressed)
        #endif
    }
}

/// List rows with a hover background highlight.
struct InteractiveRowStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.Radius.standard
    var hoverColor: Color = .primary.opacity(0.06)

    #if os(macOS)
    @State private var isHovering = false
    #endif

    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovering || configuration.isPressed ? hoverColor : .clear)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(AppAnimation.quick, value: configuration.isPressed)
            .animation(AppAnimation.quick, value: isHovering)
            .onHover { isHovering = $0 }
        #else
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? hoverColor : .clear)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(AppAnimation.quick, value: configuration.isPressed)
        #endif
    }
}

/// Subtle press feedback for icon buttons.
struct PressableButtonStyle: ButtonStyle {
    var pressScale: CGFloat = {
        #if os(iOS)
        return 0.96
        #else
        return 0.9
        #endif
    }()
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? pressScale : 1.0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1.0) : 0.45)
            .animation(reduceMotion ? nil : AppAnimation.quick, value: configuration.isPressed)
            .animation(AppAnimation.quick, value: isEnabled)
    }
}

/// Branded treatment for a page's single primary action.
///
/// Keeps the action visually consistent with playback CTAs while preserving
/// the native 44pt minimum target and Reduce Motion behavior.
struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(minHeight: 48)
            .background {
                Capsule()
                    .fill(
                        isEnabled
                            ? AnyShapeStyle(Theme.accentGradient)
                            : AnyShapeStyle(Color.secondary.opacity(0.25))
                    )
            }
            .overlay {
                Capsule()
                    .stroke(.white.opacity(isEnabled ? 0.14 : 0.06), lineWidth: 0.5)
            }
            .shadow(
                color: isEnabled ? Theme.accent.opacity(0.24) : .clear,
                radius: 8,
                y: 3
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : AppAnimation.quick, value: configuration.isPressed)
    }
}

/// Filter chips (category pickers).
struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(macOS)
    @State private var isHovering = false
    #endif

    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        configuration.label
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(.primary.opacity(isHovering ? 0.1 : 0.06))
                )
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.03 : 1.0))
            .animation(AppAnimation.spring, value: configuration.isPressed)
            .animation(AppAnimation.spring, value: isHovering)
            .onHover { isHovering = $0 }
        #else
        configuration.label
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(.primary.opacity(0.06))
                )
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : AppAnimation.quick, value: configuration.isPressed)
            .frame(minHeight: Theme.Layout.minimumTouchTarget)
            .contentShape(Rectangle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        #endif
    }
}

extension ButtonStyle where Self == InteractiveCardStyle {
    static var interactiveCard: InteractiveCardStyle { InteractiveCardStyle() }
}

extension ButtonStyle where Self == InteractiveRowStyle {
    static var interactiveRow: InteractiveRowStyle { InteractiveRowStyle() }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    static var primaryAction: PrimaryActionButtonStyle { PrimaryActionButtonStyle() }
}

extension ButtonStyle where Self == ChipButtonStyle {
    static func chip(isSelected: Bool) -> ChipButtonStyle { ChipButtonStyle(isSelected: isSelected) }
}

extension View {
    /// Preserves compact visual chrome while guaranteeing Apple's minimum
    /// touch target on iOS. Desktop keeps its denser pointer-oriented layout.
    @ViewBuilder
    func minimumInteractiveSize() -> some View {
        #if os(iOS)
        frame(
            minWidth: Theme.Layout.minimumTouchTarget,
            minHeight: Theme.Layout.minimumTouchTarget
        )
        .contentShape(Rectangle())
        #else
        self
        #endif
    }
}

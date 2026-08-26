import SwiftUI

/// 全局配色与字体，保证两个比较视图风格统一，明暗模式自适应
enum Theme {
    enum Spacing {
        static let xSmall = UIQualityPolicy.spacing[0]
        static let small = UIQualityPolicy.spacing[1]
        static let medium = UIQualityPolicy.spacing[2]
        static let large = UIQualityPolicy.spacing[3]
        static let xLarge = UIQualityPolicy.spacing[4]
        static let xxLarge = UIQualityPolicy.spacing[5]
    }

    enum Radius {
        static let control = UIQualityPolicy.cornerRadii[0]
        static let compact = UIQualityPolicy.cornerRadii[1]
        static let panel = UIQualityPolicy.cornerRadii[2]
        static let hero = UIQualityPolicy.cornerRadii[3]
    }

    static let panelBackground = Color(nsColor: .controlBackgroundColor)
    static let subtleBackground = Color.primary.opacity(0.035)
    static let hoverBackground = Color.primary.opacity(0.055)
    static let selectedBackground = Color.accentColor.opacity(0.12)
    static let panelBorder = Color.primary.opacity(0.085)
    static let strongDivider = Color.primary.opacity(0.16)

    static let addedBg = Color.green.opacity(0.16)
    static let addedHighlight = Color.green.opacity(0.45)
    static let removedBg = Color.red.opacity(0.14)
    static let removedHighlight = Color.red.opacity(0.42)
    static let modifiedLeftBg = Color.red.opacity(0.12)
    static let modifiedRightBg = Color.green.opacity(0.12)
    /// 另一侧不存在时的占位底色
    static let emptyBg = Color.primary.opacity(0.045)
    static let gutterDivider = Color.primary.opacity(0.12)

    static let mono = Font.system(size: 12, design: .monospaced)
    static let monoSmall = Font.system(size: 11, design: .monospaced)

    static func mono(size: Double) -> Font {
        .system(size: size, design: .monospaced)
    }
}

struct PanelSurfaceModifier: ViewModifier {
    var radius = Theme.Radius.panel
    var elevated = false

    func body(content: Content) -> some View {
        content
            .background(Theme.panelBackground, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.panelBorder)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: elevated ? .black.opacity(0.06) : .clear,
                radius: elevated ? 8 : 0,
                y: elevated ? 3 : 0)
    }
}

struct ContextBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .controlSize(.small)
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.vertical, Theme.Spacing.small)
            .background(.bar)
    }
}

extension View {
    func panelSurface(radius: CGFloat = Theme.Radius.panel, elevated: Bool = false) -> some View {
        modifier(PanelSurfaceModifier(radius: radius, elevated: elevated))
    }

    func contextBar() -> some View {
        modifier(ContextBarModifier())
    }
}

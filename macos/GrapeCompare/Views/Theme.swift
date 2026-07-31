import SwiftUI

/// 全局配色与字体，保证两个比较视图风格统一，明暗模式自适应
enum Theme {
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
}

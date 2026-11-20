// SPDX-License-Identifier: MIT
import SwiftUI

extension View {
    /// A control's or card's backing in the theme's style (`controls`). Without one it's the ink at
    /// `strength` in `shape`, exactly as Black draws it. `strength` is what the control already uses
    /// (more for a hovered row, less for a field), so its states still read in every style; at 0 it
    /// draws nothing.
    public func themePlatter(_ strength: Double, in shape: some Shape) -> some View {
        modifier(ThemePlatter(strength: strength, shape: AnyShape(shape)))
    }

    /// The text of a tab or segment, `lit` while it's chosen: the ink, or the ink at `unlit`, and on
    /// an accent or block selection (`SelectionMark`) the accent's own ink.
    public func themeSelectionInk(_ lit: Bool, unlit: Double = 0.7) -> some View {
        modifier(SelectionInk(lit: lit, unlit: unlit))
    }
}

extension Theme {
    /// A text field's placeholder in the theme's body face, for `TextField(_:text:prompt:)`: macOS
    /// draws a placeholder in the system font unless it comes as the field's prompt.
    public func prompt(_ placeholder: String, _ style: Font.TextStyle = .body) -> Text {
        Text(placeholder).font(font(.body, style))
    }
}

/// What marks the chosen tab or segment, in the theme's selection style (`controls.selection`):
/// the ink at `strength` in `shape` (Black's pill), an accent pill or square block, a line in the
/// accent under it, or a lit dot. Put it behind the chosen one; it can travel between them with
/// `matchedGeometryEffect`.
public struct SelectionMark: View {
    let shape: AnyShape
    let strength: Double
    @Environment(\.theme) private var theme

    public init(in shape: some Shape = Capsule(), strength: Double = 0.16) {
        self.shape = AnyShape(shape)
        self.strength = strength
    }

    public var body: some View {
        switch theme.controls?.selection ?? .pill {
        case .pill: shape.fill(.themeInk.opacity(strength))
        case .accent: shape.fill(.themeAccent)
        case .block: Rectangle().fill(.themeAccent)
        case .underline:
            Rectangle().fill(.themeAccent).frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.horizontal, 4)
        case .dot:
            Circle().fill(.themeAccent).frame(width: 4, height: 4)
                .shadow(color: theme.color(.accent), radius: 3)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: 4)  // under the label, clear of its letters
        }
    }
}

extension Theme {
    /// Whether the chosen tab or segment sits on the accent, so its text takes `onAccent`.
    public var selectsOnAccent: Bool { controls?.selection == .accent || controls?.selection == .block }
}

private struct SelectionInk: ViewModifier {
    let lit: Bool
    let unlit: Double
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.foregroundStyle(
            lit && theme.selectsOnAccent ? ThemeStyle.themeOnAccent : .themeInk.opacity(lit ? 1 : unlit))
    }
}

private struct ThemePlatter: ViewModifier {
    let strength: Double
    let shape: AnyShape
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        if let controls = theme.controls {
            let shape =
                controls.radius.map { AnyShape(RoundedRectangle(cornerRadius: $0, style: .continuous)) } ?? shape
            let line = controls.lineColor?.color ?? theme.color(.ink).opacity(min(1, 0.3 + strength * 2.5))
            content.background {
                if strength > 0 {
                    ZStack {
                        if controls.shadow == .hard {
                            shape.fill(line).offset(x: 2, y: 2)
                            shape.fill(theme.surface.color.color)  // keeps the shadow behind
                        }
                        switch controls.style ?? .fill {
                        case .fill:
                            shape.fill(.themeInk.opacity(strength))
                        case .outline:
                            shape.fill(.themeInk.opacity(strength * 0.5))
                            shape.stroke(line, lineWidth: controls.line ?? 1)
                        case .well:
                            shape.fill(controls.well?.color ?? .black)
                            shape.fill(.themeInk.opacity(strength * 0.5))
                            shape.stroke(
                                controls.lineColor?.color ?? .white.opacity(0.12), lineWidth: controls.line ?? 1)
                        }
                    }
                }
            }
        } else {
            content.background(.themeInk.opacity(strength), in: shape)
        }
    }
}

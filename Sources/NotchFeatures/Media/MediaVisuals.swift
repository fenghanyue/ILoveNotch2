// SPDX-License-Identifier: MIT
import NotchTheme
import SwiftUI

/// A seek bar whose played part is a travelling sine wave, in the spirit of the media players in
/// Android 13 and One UI: it ripples while music plays and flattens smoothly when it pauses. The
/// theme sets its line (`seekBar`); every theme keeps the wave.
struct WavySeekBar: View, Animatable {
    /// How far through the track, 0...1.
    var progress: Double
    /// 1 while playing, 0 when paused; animating it eases the wave in and out.
    var amplitude: Double
    /// How far the wave has travelled, in radians; advances with time while playing.
    var phase: Double
    var tint: Color

    @Environment(\.theme) private var theme

    nonisolated var animatableData: Double {
        get { amplitude }
        set { amplitude = newValue }
    }

    var body: some View {
        let style = theme.seekBar
        let rested = theme.color(.ink).opacity(0.22)
        let headTint = style.headFill.map { $0 == .artwork ? tint : theme.color($0, artwork: nil) } ?? tint
        let gradient = style.fill == .gradient ? Gradient(colors: theme.gradient) : nil
        return Canvas { context, size in
            let midY = size.height / 2
            let lineWidth = style.line
            let cap = style.cap.lineCap
            let playedX = size.width * min(max(progress, 0), 1)
            var rest = Path()
            rest.move(to: CGPoint(x: playedX, y: midY))
            rest.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(rest, with: .color(rested), style: Self.stroke(style.rest, width: lineWidth, cap: cap))

            let height = (size.height / 2 - lineWidth) * amplitude
            let wavelength: CGFloat = 24
            func y(_ x: CGFloat) -> CGFloat { midY + sin(x / wavelength * 2 * .pi - phase) * height }
            var wave = Path()
            wave.move(to: CGPoint(x: 0, y: y(0)))
            for x in stride(from: 2, through: playedX, by: 2) { wave.addLine(to: CGPoint(x: x, y: y(x))) }
            wave.addLine(to: CGPoint(x: playedX, y: y(playedX)))
            // A gradient fill runs the glow's colors along the whole bar, so the wave changes color as
            // it plays.
            let shading: GraphicsContext.Shading =
                gradient.map {
                    .linearGradient($0, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                } ?? .color(tint)
            context.stroke(
                wave, with: shading, style: Self.stroke(style.played ?? .solid, width: lineWidth, cap: cap))

            // The play head: a short rounded bar, a dot, or a square-cornered block.
            switch style.head {
            case .bar:
                let head = CGRect(x: playedX - 2.5, y: midY - 8, width: 5, height: 16)
                context.fill(Path(roundedRect: head, cornerRadius: 2.5), with: .color(headTint))
            case .dot:
                context.fill(
                    Path(ellipseIn: CGRect(x: playedX - 6, y: midY - 6, width: 12, height: 12)), with: .color(headTint))
            case .block:
                context.fill(Path(CGRect(x: playedX - 3, y: midY - 9, width: 6, height: 18)), with: .color(headTint))
            }
        }
    }

    /// A solid line, or round dots as wide as the line with a dot's width between them.
    private static func stroke(_ line: Theme.SeekBar.Line, width: CGFloat, cap: CGLineCap) -> StrokeStyle {
        switch line {
        case .solid: StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: .round)
        case .dotted: StrokeStyle(lineWidth: width, lineCap: .round, dash: [0, width * 1.8])
        case .dashed: StrokeStyle(lineWidth: width, lineCap: .butt, dash: [6, 6])
        }
    }
}

/// The waveform along the bottom of the player. While OpenNotch can hear what's playing, each bar
/// follows the loudness of a band of frequencies, bass in the middle and treble at the ends;
/// otherwise layered sine waves stand in. Bars settle flat when paused.
struct Waveform: View, Animatable {
    /// 1 while playing, 0 when paused; animating it settles the bars.
    var level: Double
    /// Seconds; advances while playing.
    var time: Double
    var tint: Color
    /// Loudness per band, 0...1, lowest frequencies first; empty for the stand-in motion.
    var bands: [Float] = []

    @Environment(\.theme) private var theme

    nonisolated var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        let style = theme.waveform
        let peak = style.peak.map { $0 == .artwork ? tint : theme.color($0, artwork: nil) }
        let colors = style.fill == .gradient ? theme.gradient : nil
        return Canvas { context, size in
            let step = style.bar + style.gap
            let barWidth = style.bar
            let corner = style.shape == .round ? barWidth / 2 : 0
            let count = Int(size.width / step)
            let middle = Double(count - 1) / 2
            for index in 0..<count {
                let fromMiddle = middle > 0 ? abs(Double(index) - middle) / middle : 0
                let energy = (bands.isEmpty ? motion(at: index) : loudness(at: fromMiddle)) * level
                let height = max(3, size.height * (0.1 + 0.9 * energy))
                let x = CGFloat(index) * step
                // A gradient fill steps through the glow's colors from left to right.
                let base = colors.map { $0[min(index * $0.count / max(count, 1), $0.count - 1)] } ?? tint
                let lit = base.opacity(0.3 + 0.5 * energy)
                let color = energy > 0.82 ? peak ?? lit : lit
                if style.shape == .led {
                    // Lit segments, 3 pt with 2 pt between, standing on the bottom.
                    let segments = max(1, Int((height + 2) / 5))
                    for segment in 0..<segments {
                        let y = size.height - CGFloat(segment + 1) * 5 + 2
                        context.fill(Path(CGRect(x: x, y: y, width: barWidth, height: 3)), with: .color(color))
                    }
                } else {
                    let bar = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    context.fill(Path(roundedRect: bar, cornerRadius: corner), with: .color(color))
                }
            }
        }
    }

    /// The stand-in: layered sine waves travelling across the bars.
    private func motion(at index: Int) -> Double {
        let i = Double(index)
        return 0.55 + 0.25 * sin(time * 3.1 + i * 0.35) + 0.15 * sin(time * 5.7 + i * 0.83)
            + 0.05 * sin(time * 11.3 + i * 2.1)
    }

    /// The band at `position` from the middle (0) to either end (1), blended between neighbours.
    private func loudness(at position: Double) -> Double {
        let place = min(max(position, 0), 1) * Double(bands.count - 1)
        let lower = Int(place)
        let upper = min(lower + 1, bands.count - 1)
        let blend = place - Double(lower)
        return Double(bands[lower]) * (1 - blend) + Double(bands[upper]) * blend
    }
}

/// A VU meter for the Hi-Fi player: a cream face with its scale, red zone, and ticks, and a needle
/// that swings with the loudest of the lower bands (`channel` 0) or the upper ones (1), or sways
/// while nothing can be heard. It rests at the left when paused. The face is the meter's own
/// artwork, in its own colors whatever the accent.
struct VUMeter: View, Animatable {
    /// 1 while playing, 0 when paused; animating it lays the needle down.
    var level: Double
    var time: Double
    var bands: [Float] = []
    var channel: Int

    nonisolated var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    private static let face = Color(red: 0xF5 / 255, green: 0xDF / 255, blue: 0xA8 / 255)
    private static let ink = Color(red: 0x2A / 255, green: 0x24 / 255, blue: 0x20 / 255)
    private static let red = Color(red: 0xC4 / 255, green: 0x35 / 255, blue: 0x2B / 255)

    var body: some View {
        Canvas { context, size in
            let outline = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8)
            context.fill(outline, with: .color(Self.face))
            context.clip(to: outline)
            // The needle pivots below the face; 0° points straight up, the scale runs ±45°.
            let pivot = CGPoint(x: size.width / 2, y: size.height * 1.2)
            let radius = size.height * 0.95
            func point(_ degrees: Double, _ distance: CGFloat) -> CGPoint {
                let angle = degrees * .pi / 180
                return CGPoint(x: pivot.x + distance * sin(angle), y: pivot.y - distance * cos(angle))
            }
            func arc(from start: Double, to end: Double) -> Path {
                Path { path in
                    path.move(to: point(start, radius))
                    for degrees in stride(from: start, through: end, by: 1) { path.addLine(to: point(degrees, radius)) }
                }
            }
            context.stroke(arc(from: -45, to: 45), with: .color(Self.ink), lineWidth: 1.5)
            context.stroke(arc(from: 22, to: 45), with: .color(Self.red), lineWidth: 4)
            for degrees in stride(from: -45.0, through: 45, by: 18) {
                let tick = Path { $0.addLines([point(degrees, radius), point(degrees, radius - 6)]) }
                context.stroke(tick, with: .color(Self.ink), lineWidth: 1)
            }
            context.draw(
                Text("VU").font(.system(size: 12, design: .serif).italic()).foregroundStyle(Self.ink),
                at: CGPoint(x: size.width / 2, y: size.height * 0.62))
            context.draw(
                Text(channel == 0 ? "L" : "R").font(.system(size: 8, weight: .bold)).foregroundStyle(Self.ink),
                at: CGPoint(x: 9, y: size.height - 9))
            let needle = Path { $0.addLines([pivot, point(-45 + 90 * min(max(energy * level, 0), 1), radius + 4)]) }
            context.stroke(needle, with: .color(.black.opacity(0.9)), lineWidth: 1.6)
        }
    }

    private var energy: Double {
        guard !bands.isEmpty else {
            let shift = Double(channel) * 1.7
            return 0.55 + 0.2 * sin(time * 2.3 + shift) + 0.1 * sin(time * 6.1 + shift)
        }
        let half = bands.count / 2
        return Double((channel == 0 ? bands[..<half] : bands[half...]).max() ?? 0)
    }
}

/// Shrinks a little while pressed and springs back, so controls feel physical.
public struct PressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

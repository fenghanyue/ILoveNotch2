// SPDX-License-Identifier: MIT
import NotchTheme
import SwiftUI

/// Download in Vercel's Geist blue and upload in its amber: the dark-mode pair NetSpeed's palette
/// validator picked to tell apart with any color vision, each with a lighter step for gradients.
/// A theme's `colors.series` gives its own pair, which a light theme needs.
struct NetworkTint {
    let down: Color
    let downLight: Color
    let up: Color
    let upLight: Color
    /// Text in each: the lighter step on Black's sheet, a theme's own pair as it is.
    let downInk: Color
    let upInk: Color

    init(_ theme: Theme) {
        if let series = theme.colors.series, series.count >= 2 {
            (down, up) = (series[0].color, series[1].color)
            (downLight, upLight) = (down.opacity(0.6), up.opacity(0.6))
            (downInk, upInk) = (down, up)
        } else {
            down = Color(red: 0.196, green: 0.569, blue: 1)  // #3291FF
            downLight = Color(red: 0.51, green: 0.76, blue: 1)  // #82C2FF
            up = Color(red: 0.851, green: 0.467, blue: 0.024)  // #D97706
            upLight = Color(red: 0.98, green: 0.73, blue: 0.33)  // #FABA54
            // The lighter steps would wash out on a light sheet.
            (downInk, upInk) = theme.appearance == .light ? (down, up) : (downLight, upLight)
        }
    }

    /// Lit from the top, like the Sound tab's faders.
    var downFill: LinearGradient { lit(down, from: downLight) }
    var upFill: LinearGradient { lit(up, from: upLight) }

    private func lit(_ color: Color, from light: Color) -> LinearGradient {
        LinearGradient(colors: [light, color], startPoint: .top, endPoint: .bottom)
    }
}

/// How the tab draws in a theme, from its tokens: soft rows and bars lit from the top, now's bar
/// glowing; on a light sheet, a printed ledger, its row names in the display face with dotted
/// leaders to the totals, the upload hatched; and where the theme draws its tabs as a terminal, rows
/// like du's output with dashed leaders, solid rx under hollow tx.
private enum LedgerLook {
    case soft, printed, console

    init(_ theme: Theme) {
        if theme.skin(.tabRow) == "terminal" {
            self = .console
        } else {
            self = theme.appearance == .light ? .printed : .soft
        }
    }

    /// Leaders, printed rules, and the outlines of slots still to come: dotted in print, else dashed.
    var dash: StrokeStyle {
        self == .printed
            ? StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.5, 2.5]) : StrokeStyle(lineWidth: 1, dash: [3, 2])
    }

    /// Words as the look writes them: lowercase in a console.
    func words(_ text: String) -> String { self == .console ? text.lowercased() : text }
}

/// The Network tab as a ledger: today, this week, and this month so far beside the picked range as a
/// page of bars, under a strip with the speed now and the last minute's sparkline. The strip swaps
/// the ledger for the minute's graph and back. A short notch keeps every part, smaller.
struct NetworkView: View {
    let network: NetworkFeature
    /// The minute's graph shows in the ledger's place.
    @State private var minute: Bool

    init(network: NetworkFeature, minute: Bool = false) {
        self.network = network
        _minute = State(initialValue: minute)
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 140
            VStack(spacing: compact ? 5 : 8) {
                LiveStrip(network: network, compact: compact, open: $minute)
                HStack(spacing: compact ? 8 : 10) {
                    ZStack {
                        if minute {
                            MinuteGraph(network: network, compact: compact) { minute = false }
                                .transition(.opacity)
                        } else {
                            Ledger(network: network, compact: compact)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: min(max(proxy.size.width * 0.44, 132), 236))
                    Page(network: network, compact: compact)
                }
            }
            .animation(.easeOut(duration: 0.2), value: minute)
        }
    }
}

// MARK: The live strip

/// The speed now, download and upload, beside the last minute's sparkline and its peak: a reading a
/// second, never tweened between. A click shows the minute's graph in the ledger's place, or goes
/// back.
private struct LiveStrip: View {
    let network: NetworkFeature
    let compact: Bool
    @Binding var open: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        let look = LedgerLook(theme)
        let tint = NetworkTint(theme)
        let down = NetworkFeature.speed(network.rate.down)
        let up = NetworkFeature.speed(network.rate.up)
        let peak = network.recent.map(\.rate.down).max() ?? 0
        Button {
            open.toggle()
        } label: {
            HStack(spacing: compact ? 7 : 10) {
                live(look, tint: tint)
                Group {
                    Flow(upload: false, amount: "\(down.value) \(down.unit)").foregroundStyle(tint.downInk)
                    Flow(upload: true, amount: "\(up.value) \(up.unit)").foregroundStyle(tint.upInk)
                }
                .themeFont(.numbers, size: compact ? 11 : 12.5, weight: .bold, design: .rounded)
                MinuteCanvas(samples: network.recent)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 14 : 18)
                if peak > 0 {
                    let speed = NetworkFeature.speed(peak)
                    Text(look.words(look == .console ? "Max" : "Peak") + " \(speed.value) \(speed.unit)")
                        .themeFont(.body, size: compact ? 9 : 9.5, weight: .medium)
                        .foregroundStyle(.themeSecondary)
                        .fixedSize()
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, look == .printed ? 2 : compact ? 8 : 10)
            .frame(height: compact ? 22 : 26)
            .background { backing(look) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(open ? "Back to the totals" : "The last minute's graph")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network speed")
        .accessibilityValue("\(Self.spoken(down)) down, \(Self.spoken(up)) up")
        .accessibilityHint(open ? "Goes back to the totals" : "Shows the last minute's graph")
        .accessibilityAddTraits(.isButton)
    }

    /// A lit dot and Live; a square one in a console; in print, Now in the display face.
    private func live(_ look: LedgerLook, tint: NetworkTint) -> some View {
        HStack(spacing: 5) {
            switch look {
            case .soft: Circle().fill(tint.down).frame(width: 6, height: 6).shadow(color: tint.down, radius: 3)
            case .console: Rectangle().fill(tint.down).frame(width: 6, height: 6)
            case .printed: EmptyView()
            }
            if look == .printed {
                Text("Now").themeFont(.display, size: compact ? 12 : 14, weight: .semibold)
            } else {
                Text(look.words("Live"))
                    .themeFont(.body, size: compact ? 9.5 : 10.5, weight: .semibold)
                    .foregroundStyle(.themeSecondary)
            }
        }
        .fixedSize()
    }

    /// The theme's platter; in print, a table's head: a hairline over it and a double rule under it.
    @ViewBuilder private func backing(_ look: LedgerLook) -> some View {
        if look == .printed {
            VStack(spacing: 0) {
                Rectangle().frame(height: 1)
                Spacer(minLength: 0)
                Rectangle().frame(height: 1).padding(.bottom, 1)
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(.themeInk.opacity(0.75))
        } else {
            Color.clear.themePlatter(
                open ? 0.12 : 0.07, in: RoundedRectangle(cornerRadius: compact ? 11 : 13, style: .continuous))
        }
    }

    static func spoken(_ speed: (value: String, unit: String)) -> String {
        "\(speed.value) \(speed.unit.replacingOccurrences(of: "/s", with: " per second"))"
    }
}

/// The last minute in the ledger's place, with its peaks; a click on it, or on the strip, goes back
/// to the totals.
private struct MinuteGraph: View {
    let network: NetworkFeature
    let compact: Bool
    let close: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        let look = LedgerLook(theme)
        let tint = NetworkTint(theme)
        let down = NetworkFeature.speed(network.recent.map(\.rate.down).max() ?? 0)
        let up = NetworkFeature.speed(network.recent.map(\.rate.up).max() ?? 0)
        Button(action: close) {
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                HStack(spacing: 6) {
                    Text(look.words("Last minute"))
                        .themeFont(look == .printed ? .display : .body, size: compact ? 10.5 : 12, weight: .semibold)
                    Spacer(minLength: 4)
                    ThemeSymbol("xmark")
                        .themeFont(.body, size: compact ? 8 : 9, weight: .bold)
                        .foregroundStyle(.themeSecondary)
                }
                HStack(spacing: 6) {
                    Text(look.words(look == .console ? "Max" : "Peak")).foregroundStyle(.themeSecondary)
                    Flow(upload: false, amount: "\(down.value) \(down.unit)").foregroundStyle(tint.downInk)
                    Flow(upload: true, amount: "\(up.value) \(up.unit)").foregroundStyle(tint.upInk)
                }
                .themeFont(.numbers, size: compact ? 9 : 10, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .lineLimit(1)
                MinuteCanvas(samples: network.recent, full: true)
            }
            .padding(compact ? 6 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .themePlatter(0.05, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back to the totals")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The last minute")
        .accessibilityValue("Peak \(LiveStrip.spoken(down)) down, \(LiveStrip.spoken(up)) up")
        .accessibilityHint("Goes back to the totals")
        .accessibilityAddTraits(.isButton)
    }
}

/// The last minute of speed, a reading a second, scaled to its peak (never below 100 KB/s, so idle
/// chatter stays a ripple): the download as an area under a line, or a column a second where the
/// theme's meters are LEDs. `full`, the graph in the ledger's place, adds the upload (a line, or
/// hollow columns on the download's) and on soft sheets lights the line, with a dot on its latest
/// reading. Drawn once per reading, never animated in between.
private struct MinuteCanvas: View {
    let samples: [RateSample]
    var full = false

    @Environment(\.theme) private var theme

    var body: some View {
        let tint = NetworkTint(theme)
        let look = LedgerLook(theme)
        let blocky = theme.waveform.shape == .led
        let ink = theme.color(.ink)
        Canvas { context, size in
            if full {
                let baseline = Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1))
                context.fill(baseline, with: .color(ink.opacity(0.08)))
            }
            guard samples.count > 1, let latest = samples.last?.at else { return }
            let tallest = samples.map { sample in
                guard full else { return sample.rate.down }
                return blocky ? sample.rate.down + sample.rate.up : max(sample.rate.down, sample.rate.up)
            }
            let peak = max(tallest.max() ?? 0, 100_000)
            let top: CGFloat = full ? 8 : 1
            let width = size.width - (full && !blocky ? 4 : 0)  // room for the dot on the latest reading
            func x(_ sample: RateSample) -> CGFloat {
                width * (1 - latest.timeIntervalSince(sample.at) / NetworkFeature.window)
            }
            func height(_ value: Double) -> CGFloat { (size.height - top) * min(value / peak, 1) }
            if blocky {
                let step = size.width / NetworkFeature.window  // a second's column
                for sample in samples {
                    let down = height(sample.rate.down)
                    let left = x(sample) - step
                    let column = CGRect(x: left, y: size.height - down, width: max(step - 1, 1), height: down)
                    context.fill(Path(column), with: .color(tint.down))
                    guard full, sample.rate.up > 0 else { continue }
                    let up = max(height(sample.rate.up), 1)
                    let box = CGRect(x: left + 0.5, y: column.minY - up - 0.5, width: max(step - 2, 0.5), height: up)
                    context.stroke(Path(box), with: .color(tint.up), lineWidth: 1)
                }
                return
            }
            let down = samples.map { CGPoint(x: x($0), y: size.height - height($0.rate.down)) }
            let line = Self.smooth(down)
            var area = line
            area.addLine(to: CGPoint(x: down[down.count - 1].x, y: size.height))
            area.addLine(to: CGPoint(x: down[0].x, y: size.height))
            area.closeSubpath()
            let shade: GraphicsContext.Shading =
                look == .soft
                ? .linearGradient(
                    Gradient(colors: [tint.down.opacity(0.5), tint.down.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height))
                : .color(tint.down.opacity(0.14))
            context.fill(area, with: shade)
            let style = StrokeStyle(lineWidth: full ? 1.6 : 1.4, lineCap: .round, lineJoin: .round)
            if full {
                let up = samples.map { CGPoint(x: x($0), y: size.height - height($0.rate.up)) }
                context.stroke(
                    Self.smooth(up), with: .color(tint.up),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
            guard full, look == .soft else {
                context.stroke(line, with: .color(tint.downInk), style: style)
                return
            }
            context.drawLayer { glow in
                glow.addFilter(.shadow(color: tint.down, radius: 3))
                glow.stroke(line, with: .color(tint.downLight), style: style)
                let head = down[down.count - 1]
                let dot = CGRect(x: head.x - 3, y: head.y - 3, width: 6, height: 6)
                glow.fill(Path(ellipseIn: dot), with: .color(ink))
            }
        }
        .accessibilityHidden(true)
    }

    /// Through the midpoints between readings, curving at each reading: smooth without overshooting.
    private static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for (previous, point) in zip(points, points.dropFirst()) {
            path.addQuadCurve(
                to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2), control: previous)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

// MARK: The ledger

/// Today, this week, and this month so far: each a row with its total, a bar for its share of the
/// month, and its download and upload. A row opens its page; the picked one carries the theme's
/// selection mark, which slides to the next pick, or fades there with Reduce Motion.
private struct Ledger: View {
    let network: NetworkFeature
    let compact: Bool

    @Namespace private var selection

    var body: some View {
        let month = network.soFar(.month).total
        VStack(spacing: compact ? 2 : 4) {
            ForEach([HistoryRange.day, .week, .month]) { range in
                LedgerRow(
                    range: range, traffic: network.soFar(range), month: month, picked: network.range == range,
                    compact: compact, selection: selection
                ) {
                    network.range = range
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: network.range)
    }
}

/// A period's name, a leader to its total, its share of the month, and its download and upload with
/// where it counts from, when that fits. A pill, an accent, or a block marks the whole row when it's
/// picked, its words in the accent's ink; an underline or a dot marks its name.
private struct LedgerRow: View {
    let range: HistoryRange
    let traffic: Traffic
    /// The month so far, which the bar shows a share of.
    let month: Int64
    let picked: Bool
    let compact: Bool
    let selection: Namespace.ID
    let open: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let look = LedgerLook(theme)
        let style = theme.controls?.selection ?? .pill
        let marksRow = style != .underline && style != .dot
        let inverted = picked && theme.selectsOnAccent
        let total = NetworkFeature.amount(traffic.total)
        let since = look.words(range.since(numeric: look == .console))
        Button(action: open) {
            VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(look.words(range.ledgerTitle))
                        .themeFont(
                            look == .printed ? .display : .body,
                            size: look == .printed ? (compact ? 12.5 : 15.5) : (compact ? 11 : 12.5),
                            weight: look == .console ? .bold : .semibold
                        )
                        .background {
                            if picked, !marksRow { mark }
                        }
                        .layoutPriority(1)
                    leader(look, inverted: inverted)
                    Group {
                        Text(total.value)
                            .themeFont(
                                .numbers, size: compact ? 13 : 17, weight: look == .printed ? .semibold : .bold,
                                design: .rounded)
                        Text(total.unit)
                            .themeFont(.body, size: compact ? 8.5 : 10, weight: .semibold)
                            .opacity(0.62)
                            .padding(.leading, 2)
                    }
                    .layoutPriority(1)
                }
                .themeSelectionInk(picked, unlit: 1)
                ShareBar(traffic: traffic, month: month, color: inverted ? theme.color(.onAccent) : nil)
                    .frame(height: compact ? 3 : 5)
                if !compact {
                    ViewThatFits(in: .horizontal) {
                        caption(since: since, inverted: inverted)
                        caption(since: nil, inverted: inverted)
                    }
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 1 : 4)
            .frame(maxHeight: .infinity)
            .background {
                if picked, marksRow {
                    mark
                } else if hovering, !picked {
                    Color.clear.themePlatter(0.05, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
            }
            .overlay(alignment: .bottom) {
                if look == .printed {
                    Rule().stroke(.themeInk.opacity(0.4), style: look.dash).frame(height: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(range.ledgerTitle), \(since): open its page")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(range.ledgerTitle)
        .accessibilityValue(
            "\(NetworkFeature.bytes(traffic.total)): \(NetworkFeature.bytes(traffic.down)) down, "
                + "\(NetworkFeature.bytes(traffic.up)) up, \(since)"
        )
        .accessibilityHint("Shows its page")
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    private var radius: CGFloat { theme.controls?.radius.map { CGFloat($0) } ?? 12 }

    /// The theme's selection mark, sliding between rows, or fading in place with Reduce Motion.
    @ViewBuilder private var mark: some View {
        let mark = SelectionMark(in: RoundedRectangle(cornerRadius: radius, style: .continuous), strength: 0.1)
        if reduceMotion {
            mark.transition(.opacity)
        } else {
            mark.matchedGeometryEffect(id: "row", in: selection)
        }
    }

    /// Dotted or dashed from the name to the total, at the words' baseline; soft rows leave a gap.
    @ViewBuilder private func leader(_ look: LedgerLook, inverted: Bool) -> some View {
        if look == .soft {
            Spacer(minLength: 6)
        } else {
            Rule()
                .stroke(inverted ? theme.color(.onAccent) : theme.color(.ink).opacity(0.45), style: look.dash)
                .frame(minWidth: 6, maxWidth: .infinity)
                .frame(height: 1)
                .padding(.horizontal, 5)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
        }
    }

    /// The download and upload, and where the period counts from.
    private func caption(since: String?, inverted: Bool) -> some View {
        let tint = NetworkTint(theme)
        let ink = { (color: Color) in inverted ? theme.color(.onAccent) : color }
        return HStack(spacing: 5) {
            Flow(upload: false, amount: NetworkFeature.bytes(traffic.down)).foregroundStyle(ink(tint.downInk))
            Flow(upload: true, amount: NetworkFeature.bytes(traffic.up)).foregroundStyle(ink(tint.upInk))
            Spacer(minLength: 3)
            if let since {
                Text(since).foregroundStyle(ink(theme.color(.secondary))).fixedSize()
            }
        }
        .themeFont(.body, size: 9, weight: .medium)
    }
}

/// A ledger row's share of the month: its download, then its upload, along a track the month fills.
/// `color` draws both in one color, on an inverted row.
private struct ShareBar: View {
    let traffic: Traffic
    let month: Int64
    var color: Color?

    @Environment(\.theme) private var theme

    var body: some View {
        let look = LedgerLook(theme)
        GeometryReader { proxy in
            // A week that began last month can outrun the month.
            let scale = proxy.size.width / CGFloat(max(month, traffic.total, 1))
            HStack(spacing: 0) {
                SeriesFill(upload: false, across: true, color: color).frame(width: CGFloat(traffic.down) * scale)
                SeriesFill(upload: true, across: true, color: color).frame(width: CGFloat(traffic.up) * scale)
            }
        }
        .background {
            if let color {
                Rectangle().fill(color.opacity(0.3))
            } else {
                switch look {
                case .soft: Rectangle().fill(.themeInk.opacity(0.1))
                case .printed: Rectangle().strokeBorder(.themeInk.opacity(0.45), lineWidth: 1)
                case .console: Rectangle().fill(.themeFill)
                }
            }
        }
        .clipShape(look == .soft ? AnyShape(Capsule()) : AnyShape(Rectangle()))
        .accessibilityHidden(true)
    }
}

/// Download or upload as the look fills it: lit from the top (along a row's bar, from its start) on
/// soft sheets; in print, solid download under hatched upload; in a console, solid rx under hollow
/// tx. `color` draws it in one color instead of the series'.
private struct SeriesFill: View {
    let upload: Bool
    /// Along a ledger row's bar rather than up a page's.
    var across = false
    var color: Color?

    @Environment(\.theme) private var theme

    var body: some View {
        let tint = NetworkTint(theme)
        let look = LedgerLook(theme)
        let base = color ?? (upload ? tint.up : tint.down)
        if upload, look != .soft {
            ZStack {
                if look == .printed { Hatch().stroke(base, lineWidth: 1).clipped() }
                Rectangle().strokeBorder(base, lineWidth: 1)
            }
        } else if look != .soft || color != nil {
            Rectangle().fill(base.opacity(color != nil && upload ? 0.55 : 1))
        } else if across {
            let lit = LinearGradient(colors: [tint.down, tint.downLight], startPoint: .leading, endPoint: .trailing)
            Rectangle().fill(upload ? AnyShapeStyle(tint.upLight) : AnyShapeStyle(lit))
        } else {
            Rectangle().fill(upload ? tint.upFill : tint.downFill)
        }
    }
}

/// A download or upload amount after its arrow, or after rx or tx in a console.
private struct Flow: View {
    let upload: Bool
    let amount: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            if LedgerLook(theme) == .console {
                Text(upload ? "tx" : "rx")
            } else {
                ThemeSymbol(upload ? "arrow.up" : "arrow.down").imageScale(.small)
            }
            Text(amount)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: The page

/// The picked range as a page of bars: a calendar day by the hour, a week or a month by the day, or a
/// year by the month, with what's still to come as empty slots. The switch picks the range; the
/// arrows, or ← and →, page back and forth.
private struct Page: View {
    let network: NetworkFeature
    let compact: Bool

    @Environment(\.theme) private var theme
    @State private var hovered: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    picker(short: false)
                    picker(short: true)
                }
                Spacer(minLength: 0)
                pager.layoutPriority(1)
            }
            Bars(
                buckets: network.buckets, range: network.range, current: network.page == 0, compact: compact,
                hovered: $hovered
            )
            .id("\(network.range.rawValue)\(network.page)")  // a new page rises anew
        }
        .padding(compact ? 6 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themePlatter(0.05, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: network.range)
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    /// Day, Week, Month, and Year, or D, W, M, and Y where they don't fit, the picked one marked.
    private func picker(short: Bool) -> some View {
        let look = LedgerLook(theme)
        return HStack(spacing: 0) {
            ForEach(HistoryRange.allCases) { range in
                let chosen = network.range == range
                Button {
                    hovered = nil
                    network.range = range
                } label: {
                    Text(look.words(short ? range.shortTitle : range.title))
                        .themeFont(.body, size: 10, weight: .semibold)
                        .themeSelectionInk(chosen, unlit: 0.55)
                        .padding(.horizontal, short ? 6 : 8)
                        .frame(height: compact ? 16 : 18)
                        .background {
                            if chosen { SelectionMark().transition(.opacity) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(range.caption)
                .accessibilityLabel(range.caption)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .themePlatter(0.07, in: Capsule())
        .fixedSize()
    }

    /// The page's dates between arrows to the one before and the one after; there's none after now's,
    /// and none before the history begins.
    private var pager: some View {
        let look = LedgerLook(theme)
        let range = network.range
        let page = network.pageInterval
        let earlier = page.flatMap { page in network.earliest.map { $0 < page.start } } ?? false
        let total = network.buckets.reduce(Traffic()) { $0 + $1.traffic }
        return HStack(spacing: 0) {
            arrow("chevron.left", "Earlier \(range.rawValue)", enabled: earlier) { turn(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text(page.map { range.title(of: $0, numeric: look == .console) } ?? "")
                .themeFont(
                    look == .printed ? .display : .body,
                    size: look == .printed ? (compact ? 11.5 : 13) : (compact ? 10 : 11), weight: .semibold
                )
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .help(
                    "\(NetworkFeature.bytes(total.down)) down, \(NetworkFeature.bytes(total.up)) up, "
                        + "\(NetworkFeature.bytes(total.total)) in all")
            arrow("chevron.right", "Later \(range.rawValue)", enabled: network.page < 0) { turn(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    private func arrow(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ThemeSymbol(symbol)
                .themeFont(.body, size: compact ? 8.5 : 9.5, weight: .bold)
                .frame(width: compact ? 14 : 18, height: compact ? 16 : 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.themeSecondary)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private func turn(_ pages: Int) {
        hovered = nil
        network.page += pages
    }
}

/// A page's bars, upload stacked on download and scaled to the tallest, with the slots still to come
/// outlined, over their labels; on a week, now's total stands over its bar. The pointer picks a bar
/// for its date and both totals, and the others dim.
private struct Bars: View {
    let buckets: [TrafficBucket]
    let range: HistoryRange
    /// The page now is on, so one bar is now's.
    let current: Bool
    let compact: Bool
    @Binding var hovered: Int?

    @Environment(\.theme) private var theme

    var body: some View {
        let look = LedgerLook(theme)
        let now = current ? buckets.lastIndex { !$0.upcoming } : nil
        let nowTotal = !compact && buckets.count <= 7 ? now : nil
        GeometryReader { proxy in
            let count = CGFloat(max(buckets.count, 1))
            let gap: CGFloat = buckets.count > 12 ? 2 : buckets.count > 7 ? 4 : 8
            let slot = max(1, (proxy.size.width - gap * (count - 1)) / count)
            let room = proxy.size.height - (compact ? 0 : 14) - (nowTotal == nil ? 0 : 14)
            let peak = CGFloat(max(buckets.map(\.traffic.total).max() ?? 0, 1))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                    VStack(spacing: 3) {
                        if index == nowTotal {
                            Text(NetworkFeature.bytes(bucket.traffic.total))
                                .themeFont(.numbers, size: 9.5, weight: .bold, design: .rounded)
                                .fixedSize()
                                .frame(width: slot, height: 11)
                        }
                        Bar(
                            bucket: bucket, width: min(slot, 24), scale: room / peak,
                            slot: min(24, room * 0.2, slot * 1.5), now: index == now, order: index
                        )
                        .opacity(hovered == nil || hovered == index ? 1 : 0.35)
                        if !compact {
                            // Every column keeps the label's room, so the bars share a baseline.
                            Color.clear.frame(width: slot, height: 11).overlay(
                                alignment: buckets.count > 12 ? .leading : .center
                            ) {
                                axisLabel(bucket, index: index, now: index == now, look: look)
                            }
                        }
                    }
                    .frame(width: slot)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
            .overlay(alignment: .topLeading) { callout(width: proxy.size.width, slot: slot, gap: gap) }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                // Every pointer move lands here; only crossing into another bar changes anything.
                var bar: Int?
                if case .active(let location) = phase {
                    bar = min(max(Int(location.x / (slot + gap)), 0), buckets.count - 1)
                }
                if bar != hovered { hovered = bar }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(range.caption)
        .accessibilityValue(spokenValue)
        .accessibilityAdjustableAction { direction in
            let next = (hovered ?? buckets.count) + (direction == .increment ? 1 : -1)
            hovered = buckets.indices.contains(next) ? next : nil
        }
    }

    /// Every bar's on a week and a year, every sixth hour's, and every seventh day's of a month; now's
    /// in full ink.
    @ViewBuilder
    private func axisLabel(_ bucket: TrafficBucket, index: Int, now: Bool, look: LedgerLook) -> some View {
        let every = range == .day ? 6 : range == .month ? 7 : 1
        if index % every == 0 {
            Text(look.words(range.axisLabel(bucket.start)))
                .themeFont(.body, size: 9, weight: now ? .bold : .medium)
                .foregroundStyle(now ? .themeInk : .themeSecondary)
                .fixedSize()
        }
    }

    /// The hovered bar's date and totals over the bars, centered on it and kept inside the page.
    @ViewBuilder private func callout(width: CGFloat, slot: CGFloat, gap: CGFloat) -> some View {
        if let hovered, buckets.indices.contains(hovered) {
            let center = (slot + gap) * CGFloat(hovered) + slot / 2
            Callout(bucket: buckets[hovered], range: range)
                .alignmentGuide(.leading) { -min(max(center - $0.width / 2, 0), max(width - $0.width, 0)) }
                .frame(width: width, alignment: .leading)
                .allowsHitTesting(false)
        }
    }

    private var spokenValue: String {
        let traffic: Traffic
        var prefix = ""
        if let hovered, buckets.indices.contains(hovered) {
            prefix = range.label(buckets[hovered].start) + ", "
            guard !buckets[hovered].upcoming else { return prefix + "still to come" }
            traffic = buckets[hovered].traffic
        } else {
            traffic = buckets.reduce(Traffic()) { $0 + $1.traffic }
        }
        return "\(prefix)\(NetworkFeature.bytes(traffic.down)) down, \(NetworkFeature.bytes(traffic.up)) up, "
            + "\(NetworkFeature.bytes(traffic.total)) in all"
    }
}

/// A bar's date over both its totals, or over that it's still to come.
private struct Callout: View {
    let bucket: TrafficBucket
    let range: HistoryRange

    @Environment(\.theme) private var theme

    var body: some View {
        let look = LedgerLook(theme)
        let tint = NetworkTint(theme)
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius.map { CGFloat($0) } ?? 6, style: .continuous)
        VStack(alignment: .leading, spacing: 1) {
            Text(look.words(range.label(bucket.start))).themeFont(.body, size: 9.5, weight: .semibold)
            if bucket.upcoming {
                Text(look.words("Still to come")).foregroundStyle(.themeSecondary)
            } else {
                HStack(spacing: 6) {
                    Flow(upload: false, amount: NetworkFeature.bytes(bucket.traffic.down))
                        .foregroundStyle(tint.downInk)
                    Flow(upload: true, amount: NetworkFeature.bytes(bucket.traffic.up)).foregroundStyle(tint.upInk)
                }
            }
        }
        .themeFont(.numbers, size: 9.5, weight: .semibold, design: .rounded)
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .themePlatter(0.12, in: shape)
        .background(theme.surface.color.color, in: shape)
    }
}

/// One bar: upload stacked on download, a sliver while empty so the row keeps its shape, or the
/// outline of a slot still to come. Now's is lit the look's way: a glow on soft sheets, a printed
/// shadow in print. It grows from the baseline when its page appears, a moment after the one before
/// it, or fades in place with Reduce Motion.
private struct Bar: View {
    let bucket: TrafficBucket
    let width: CGFloat
    /// Points per byte.
    let scale: CGFloat
    /// A slot's height.
    let slot: CGFloat
    let now: Bool
    /// Its place in the row, for the rising wave.
    let order: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @State private var shown = false

    var body: some View {
        let look = LedgerLook(theme)
        let radius = look == .soft ? min(width / 2, 4) : 0
        Group {
            if bucket.upcoming {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.themeInk.opacity(look == .soft ? 0.28 : 0.5), style: look.dash)
                    .frame(width: width, height: slot)
            } else if bucket.traffic.total == 0 {
                Rectangle().fill(.themeInk.opacity(0.1)).frame(width: width, height: 2)
            } else {
                stack(look, radius: radius)
            }
        }
        .scaleEffect(y: shown || reduceMotion ? 1 : 0.01, anchor: .bottom)
        .opacity(shown || !reduceMotion ? 1 : 0)
        .onAppear {
            let appear: Animation =
                reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35).delay(Double(order) * 0.02)
            withAnimation(appear) { shown = true }
        }
    }

    private func stack(_ look: LedgerLook, radius: CGFloat) -> some View {
        let up = CGFloat(bucket.traffic.up) * scale
        let down = CGFloat(bucket.traffic.down) * scale
        let gap: CGFloat = look == .soft ? 1 : look == .console ? 2 : 0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radius, bottomLeadingRadius: min(radius, 2), bottomTrailingRadius: min(radius, 2),
            topTrailingRadius: radius, style: .continuous)
        return VStack(spacing: 0) {
            if up >= 0.5 {
                SeriesFill(upload: true).frame(height: max(up, 1))
                Color.clear.frame(height: gap)
            }
            SeriesFill(upload: false).frame(height: max(down, 1))
        }
        .frame(width: width)
        .clipShape(shape)
        .background {
            if now {
                switch look {
                case .soft: shape.fill(NetworkTint(theme).down).blur(radius: 8).opacity(0.75)
                case .printed: Rectangle().fill(.themeInk.opacity(0.14)).offset(x: 2.5, y: 2.5)
                case .console: EmptyView()
                }
            }
        }
    }
}

/// A line across the middle of its frame: a leader, or a printed row's rule.
private struct Rule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Lines slanting across its frame every `spacing` points, for a printed upload.
private struct Hatch: Shape {
    var spacing: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        Path { path in
            var x = rect.minX - rect.height
            while x < rect.maxX {
                path.move(to: CGPoint(x: x, y: rect.maxY))
                path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += spacing
            }
        }
    }
}

extension HistoryRange {
    /// A ledger row's name.
    var ledgerTitle: String {
        switch self {
        case .day: "Today"
        case .week: "This week"
        case .month: "This month"
        case .year: "This year"
        }
    }

    /// Where a ledger row counts from: "since midnight", "since Monday", "since Nov 1"; `numeric`, as
    /// a log writes them: "since 00:00", "since Mon", "since 11-01".
    func since(numeric: Bool, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let start = interval(page: 0, now: now, calendar: calendar)?.start else { return "" }
        let day = calendar.dateComponents([.month, .day], from: start)
        return switch self {
        case .day: numeric ? "since 00:00" : "since midnight"
        case .week: "since " + start.formatted(.dateTime.weekday(numeric ? .abbreviated : .wide))
        case .month, .year:
            numeric
                ? String(format: "since %02d-%02d", day.month ?? 1, day.day ?? 1)
                : "since " + start.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// A page's name: "Fri, Nov 20", "Nov 16 – 22", "Nov 2026", or "2026"; `numeric`, as a log
    /// writes them: "11-20", "11-16..22", "2026-11", "2026".
    func title(of page: DateInterval, numeric: Bool, calendar: Calendar = .current) -> String {
        let start = page.start
        let last = page.end.addingTimeInterval(-1)
        let first = calendar.dateComponents([.year, .month, .day], from: start)
        let end = calendar.dateComponents([.month, .day], from: last)
        func two(_ number: Int?) -> String { String(format: "%02d", number ?? 0) }
        switch self {
        case .day:
            return numeric
                ? "\(two(first.month))-\(two(first.day))"
                : start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            guard numeric else { return (start..<last).formatted(.interval.month(.abbreviated).day()) }
            let to = first.month == end.month ? two(end.day) : "\(two(end.month))-\(two(end.day))"
            return "\(two(first.month))-\(two(first.day))..\(to)"
        case .month:
            return numeric
                ? "\(first.year ?? 0)-\(two(first.month))" : start.formatted(.dateTime.month(.abbreviated).year())
        case .year:
            return start.formatted(.dateTime.year())
        }
    }

    /// Under a bar: "6 AM", "Mon", "15", or "J".
    func axisLabel(_ date: Date) -> String {
        switch self {
        case .day: date.formatted(.dateTime.hour())
        case .week: date.formatted(.dateTime.weekday(.abbreviated))
        case .month: date.formatted(.dateTime.day())
        case .year: date.formatted(.dateTime.month(.narrow))
        }
    }

    /// A bar in full: "Tue 3 PM", "Tue 12 Sep", or "September 2026".
    func label(_ date: Date) -> String {
        switch self {
        case .day: date.formatted(.dateTime.weekday(.abbreviated).hour())
        case .week, .month: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .year: date.formatted(.dateTime.month(.wide).year())
        }
    }
}

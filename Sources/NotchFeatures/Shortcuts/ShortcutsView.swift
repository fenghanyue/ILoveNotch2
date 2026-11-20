// SPDX-License-Identifier: MIT
import NotchTheme
import SwiftUI

/// The shortcuts tab: four favorites on big pads, each in its shortcut's color, beside a log of what
/// the last runs did. Click a pad to run it; right-click it to swap in another shortcut. The log's
/// All button, and the log itself until something has run, lists every shortcut.
struct ShortcutsView: View {
    let shortcuts: ShortcutsFeature
    @State private var showsAll = false
    @Environment(\.theme) private var theme

    var body: some View {
        switch shortcuts.status {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            FeatureUnavailableView(
                symbol: "square.stack.3d.up.slash",
                title: "Shortcuts unavailable",
                message: "The shortcuts command didn't respond on this Mac.")
        case .ready where shortcuts.visible.isEmpty:
            FeatureUnavailableView(
                symbol: "square.stack.3d.up",
                title: "No shortcuts to show",
                message: "Shortcuts you make in the Shortcuts app show up here.",
                action: (label: "Open Shortcuts", perform: shortcuts.openShortcutsApp))
        case .ready:
            HStack(spacing: 12) {
                pads.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    header
                    if ShortcutsLook(theme) == .journal {
                        Rectangle().fill(.themeInk.opacity(0.55)).frame(height: 1)
                    }
                    if listing {
                        allShortcuts
                    } else {
                        RunLog(shortcuts: shortcuts)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// Every shortcut, when asked for or while nothing has run yet.
    private var listing: Bool { showsAll || shortcuts.log.isEmpty }

    private var pads: some View {
        let favorites = shortcuts.favorites
        let slot = { (index: Int) in favorites.indices.contains(index) ? favorites[index] : nil }
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                pad(slot(0))
                pad(slot(1))
            }
            HStack(spacing: 8) {
                pad(slot(2))
                pad(slot(3))
            }
        }
    }

    @ViewBuilder private func pad(_ name: String?) -> some View {
        if let name {
            Pad(name: name, shortcuts: shortcuts).id(name)
        } else {
            EmptyPad(shortcuts: shortcuts)
        }
    }

    private var header: some View {
        let look = ShortcutsLook(theme)
        let title = { (text: String) in
            Text(text)
                .themeFont(
                    look == .journal ? .display : .body, size: look == .journal ? 15 : 12,
                    weight: look == .console ? .bold : .semibold
                )
                .textCase(look == .console ? .uppercase : nil)
                .tracking(look == .console ? 0.6 : 0)
                .lineLimit(1)
        }
        return HStack(spacing: 6) {
            // The smallest notch says it in a word.
            ViewThatFits(in: .horizontal) {
                title(listing ? "All shortcuts" : "Recent runs")
                title(listing ? "All" : "Runs")
            }
            Spacer(minLength: 4)
            if !listing {
                chip("All", help: "Every shortcut") { showsAll = true }
                chip("Clear", help: "Clear the finished runs", action: shortcuts.clearLog)
                    .disabled(shortcuts.log.allSatisfy { $0.outcome == .running })
            } else if !shortcuts.log.isEmpty {
                chip("Recent", help: "The recent runs") { showsAll = false }
            }
        }
        .frame(height: 20)
    }

    private func chip(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeFont(.body, size: 10, weight: .semibold)
                .opacity(0.75)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .themePlatter(0.08, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var allShortcuts: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(shortcuts.visible, id: \.self) { name in
                    ListRow(name: name, shortcuts: shortcuts) { showsAll = false }
                }
            }
            .padding(.vertical, 4)
        }
        .fadingEdges()
    }
}

/// How the tab draws in a theme: glass pads with glowing discs and soft colored marks; on a light
/// sheet, cards with ink-stamp discs over a ruled journal; and where the theme draws its tabs as a
/// terminal, boxes over console lines tagged RUN, OK, and ERR.
private enum ShortcutsLook {
    case glass, journal, console

    init(_ theme: Theme) {
        if theme.skin(.tabRow) == "terminal" {
            self = .console
        } else {
            self = theme.appearance == .light ? .journal : .glass
        }
    }

    /// A shortcut's own color, the same in every theme. Shortcuts keeps the color and glyph the user
    /// picked where no public API reads them, so each name gets one of the Shortcuts app's colors.
    // ponytail: a hash of the name, so two shortcuts can share a color; read Shortcuts' own once
    // Apple offers a way.
    static func color(_ name: String) -> Color {
        let colors: [Color] = [.red, .orange, .green, .teal, .blue, .indigo, .purple, .pink]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF_FFFF }
        return colors[hash % colors.count]
    }

    /// A glyph for a shortcut from the first word of its name that says what it does.
    // ponytail: a keyword table; a name it misses gets the Shortcuts stack.
    static func glyph(_ name: String) -> String {
        let words = name.lowercased().split { !$0.isLetter }
        for word in words {
            if let match = glyphs.first(where: { word.hasPrefix($0.key) }) { return match.value }
        }
        return "square.stack.3d.up"
    }

    private static let glyphs: [String: String] = [
        "focus": "moon.zzz.fill", "sleep": "moon.zzz.fill", "night": "moon.zzz.fill", "bed": "moon.zzz.fill",
        "morning": "sun.max.fill", "sun": "sun.max.fill", "weather": "sun.max.fill", "water": "drop.fill",
        "drink": "drop.fill", "light": "lightbulb.fill", "lamp": "lightbulb.fill", "music": "music.note",
        "song": "music.note", "play": "music.note", "photo": "photo", "image": "photo", "picture": "photo",
        "screenshot": "photo", "resize": "photo", "timer": "timer", "pomodoro": "timer", "mail": "envelope.fill",
        "email": "envelope.fill", "message": "message.fill", "text": "message.fill",
        "translate": "character.bubble.fill", "home": "house.fill", "house": "house.fill", "note": "note.text",
        "journal": "note.text", "clipboard": "doc.on.clipboard", "copy": "doc.on.clipboard",
        "paste": "doc.on.clipboard", "calendar": "calendar", "meeting": "calendar", "event": "calendar",
        "coffee": "cup.and.saucer.fill", "link": "link", "url": "link", "web": "link", "search": "magnifyingglass",
        "find": "magnifyingglass", "share": "square.and.arrow.up", "airdrop": "square.and.arrow.up",
        "download": "arrow.down.circle", "remind": "checklist", "task": "checklist", "todo": "checklist",
    ]
}

extension Theme {
    /// A color as it reads on this sheet: on a light one, worked toward the ink, like a pigment.
    fileprivate func pigment(_ color: Color) -> Color {
        guard appearance == .light else { return color }
        if #available(macOS 15, *) { return color.mix(with: self.color(.ink), by: 0.3) }
        return color
    }

    /// A pad's corners: the theme's own for its controls, or a soft square.
    fileprivate var padRadius: CGFloat { controls?.radius.map { CGFloat($0) } ?? 16 }
}

/// A favorite: its glyph on a disc in its color, its name, and when it last ran. Hovered, it's the
/// chosen one: ringed on glass, its name underlined in a journal, inverted in a console.
private struct Pad: View {
    let name: String
    let shortcuts: ShortcutsFeature
    @State private var hovering = false
    /// Counts presses, each sending a ring out from the disc.
    @State private var presses = 0
    @Environment(\.theme) private var theme

    var body: some View {
        let look = ShortcutsLook(theme)
        let shape = RoundedRectangle(cornerRadius: theme.padRadius, style: .continuous)
        let running = shortcuts.running.contains(name)
        Button {
            presses += 1
            shortcuts.run(name)
        } label: {
            // Shorter notches shrink the disc, then drop the last run, so the name always shows.
            ViewThatFits(in: .vertical) {
                content(look, disc: 40, size: look == .journal ? 15 : look == .console ? 11 : 13, last: true)
                content(look, disc: 30, size: look == .journal ? 14 : 11, last: false)
                content(look, disc: 20, size: 10, last: false)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backing(look, in: shape) }
            .themeSelectionInk(look == .console && hovering, unlit: 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            let others = shortcuts.visible.filter { !shortcuts.favorites.contains($0) }
            if !others.isEmpty {
                Menu("Replace With") {
                    ForEach(others, id: \.self) { other in
                        Button(other) { shortcuts.replace(name, with: other) }
                    }
                }
            }
            Button("Unpin") { shortcuts.unpin(name) }
        }
        .help("Run \(name)")
        .accessibilityLabel(running ? "\(name), running" : "Run \(name)")
    }

    private func content(_ look: ShortcutsLook, disc: CGFloat, size: CGFloat, last: Bool) -> some View {
        VStack(spacing: disc >= 40 ? 6 : 3) {
            Disc(name: name, size: disc, look: look, presses: presses)
            Text(name)
                .themeFont(
                    look == .journal ? .display : .body, size: size, weight: look == .console ? .bold : .semibold
                )
                .textCase(look == .console ? .uppercase : nil)
                .tracking(look == .console ? 0.4 : 0)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.bottom, look == .journal ? 2 : 0)
                .background {
                    if look == .journal, hovering { SelectionMark(in: Rectangle()) }
                }
                .themeSelectionInk(hovering && look != .glass, unlit: 1)
            if last, let detail { Text(detail).themeFont(.body, size: 10).opacity(0.6).lineLimit(1) }
        }
    }

    @ViewBuilder private func backing(_ look: ShortcutsLook, in shape: RoundedRectangle) -> some View {
        switch look {
        case .glass:
            Color.clear.themePlatter(hovering ? 0.12 : 0.06, in: shape)
                .overlay {
                    if hovering { shape.strokeBorder(.themeInk.opacity(0.85), lineWidth: 1.5) }
                }
        case .journal:
            Color.clear.themePlatter(0.08, in: shape)
        case .console:
            if hovering { SelectionMark(in: shape) } else { Color.clear.themePlatter(0.08, in: shape) }
        }
    }

    /// When it last ran, from the log.
    private var detail: String? {
        guard let run = shortcuts.lastRun(of: name) else { return nil }
        switch run.outcome {
        case .running: return "Running"
        case .failed: return "Failed \(run.clock)"
        case .done, .stopped: return "Ran \(run.clock)"
        }
    }
}

/// A shortcut's glyph on a disc: lit in its color on glass, stamped in it on paper, boxed in a
/// console. A press sends a ring out from it, unless Reduce Motion is on.
private struct Disc: View {
    let name: String
    let size: CGFloat
    let look: ShortcutsLook
    let presses: Int
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = theme.pigment(ShortcutsLook.color(name))
        ZStack {
            switch look {
            case .glass:
                Circle().fill(color)
                Circle().fill(
                    RadialGradient(
                        colors: [theme.color(.ink).opacity(0.4), .clear], center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0, endRadius: size * 0.7))
            case .journal:
                Circle().fill(color.opacity(0.08))
                Circle().strokeBorder(color, lineWidth: 1.5)
            case .console:
                Rectangle().strokeBorder(.foreground.opacity(0.5), lineWidth: 1)
            }
            ThemeSymbol(ShortcutsLook.glyph(name))
                .themeFont(.body, size: size * 0.42, weight: .semibold)
                .foregroundStyle(look == .journal ? AnyShapeStyle(color) : AnyShapeStyle(.foreground))
        }
        .frame(width: size, height: size)
        .shadow(color: look == .glass ? color.opacity(0.55) : .clear, radius: size * 0.25, y: size * 0.1)
        .overlay {
            if !reduceMotion {
                Group {
                    if look == .console {
                        Rectangle().stroke(.foreground, lineWidth: 1.5)
                    } else {
                        Circle().stroke(color, lineWidth: 2)
                    }
                }
                .keyframeAnimator(initialValue: 0.0, trigger: presses) { ring, progress in
                    ring.scaleEffect(1 + progress * 0.5).opacity(progress > 0 && progress < 1 ? 1 - progress : 0)
                } keyframes: { _ in
                    LinearKeyframe(1.0, duration: 0.3)
                }
            }
        }
    }
}

/// A free pad: a dashed outline that picks a shortcut to pin there.
private struct EmptyPad: View {
    let shortcuts: ShortcutsFeature
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.padRadius, style: .continuous)
        let others = shortcuts.visible.filter { !shortcuts.favorites.contains($0) }
        if others.isEmpty {
            Color.clear
        } else {
            Menu {
                ForEach(others, id: \.self) { name in
                    Button(name) { shortcuts.pin(name) }
                }
            } label: {
                ThemeSymbol("plus").themeFont(.body, size: 14, weight: .semibold).opacity(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        shape.strokeBorder(.themeInk.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    .contentShape(shape)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Pin a favorite here")
            .accessibilityLabel("Pin a favorite")
        }
    }
}

/// The last runs, newest first. A new one slides in at the top; with Reduce Motion it fades in.
private struct RunLog: View {
    let shortcuts: ShortcutsFeature
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(shortcuts.log) { run in
                    LogRow(run: run, shortcuts: shortcuts)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.vertical, 2)
        }
        .fadingEdges(length: 6)
        .animation(.easeOut(duration: 0.25), value: shortcuts.log.map(\.id))
    }
}

/// What a run in the log did, as the log says it.
private enum RunKind {
    case running, done, failed, stopped, copied

    init(_ run: ShortcutsFeature.Run) {
        switch run.outcome {
        case .running: self = .running
        case .done: self = run.copied ? .copied : .done
        case .failed: self = .failed
        case .stopped: self = .stopped
        }
    }

    var word: String {
        switch self {
        case .running: "Running"
        case .done: "Done"
        case .failed: "Failed"
        case .stopped: "Stopped"
        case .copied: "Output copied"
        }
    }

    /// A console's tag for it.
    var tag: String {
        switch self {
        case .running: "RUN"
        case .done: "OK"
        case .failed: "ERR"
        case .stopped: "END"
        case .copied: "CPY"
        }
    }

    var symbol: String {
        switch self {
        case .running, .done: "checkmark"
        case .failed: "xmark"
        case .stopped: "stop.fill"
        case .copied: "doc.on.clipboard"
        }
    }

    /// Its mark's color: the theme's accent while running, green for done, red for failed.
    func hue(_ theme: Theme) -> Color {
        switch self {
        case .running: theme.pigment(theme.color(.accent))
        case .done: theme.pigment(.green)
        case .failed: theme.pigment(.red)
        case .stopped: theme.color(.tertiary)
        case .copied: theme.pigment(.blue)
        }
    }
}

extension ShortcutsFeature.Run {
    /// When it started, as a clock shows it.
    fileprivate var clock: String { started.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()) }

    /// How long it took, as "3s" or "1m 5s".
    fileprivate var took: String {
        Duration.seconds(max(1, (duration ?? 0).rounded()))
            .formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
    }

    /// Beside its word: the output, why it failed, or how long it took.
    fileprivate var detail: String {
        switch outcome {
        case .running: ""
        case .stopped: "after \(took)"
        case .failed(let reason): reason ?? "after \(took)"
        case .done:
            output.map { "\u{201C}\($0.split(whereSeparator: \.isNewline).joined(separator: " "))\u{201D}" }
                ?? "in \(took)"
        }
    }
}

/// One run: its mark, name and time, then what it did, with Stop while it runs and Retry once it
/// fails. Click one with output to copy it again.
private struct LogRow: View {
    let run: ShortcutsFeature.Run
    let shortcuts: ShortcutsFeature
    @Environment(\.theme) private var theme

    var body: some View {
        let look = ShortcutsLook(theme)
        let kind = RunKind(run)
        HStack(spacing: 8) {
            if run.output != nil {
                Button {
                    shortcuts.copyOutput(of: run.id)
                } label: {
                    summary(look, kind).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy the output")
            } else {
                summary(look, kind)
            }
            action
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background {
            if kind == .running { runningBacking(look, hue: kind.hue(theme)) }
        }
        .overlay(alignment: .bottom) {
            if look == .journal {
                Rule().stroke(.themeInk.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [1, 2])).frame(height: 1)
            }
        }
        .contextMenu {
            if run.output != nil { Button("Copy Output") { shortcuts.copyOutput(of: run.id) } }
            Button("Run Again") { shortcuts.run(run.name) }.disabled(shortcuts.running.contains(run.name))
        }
    }

    private func summary(_ look: ShortcutsLook, _ kind: RunKind) -> some View {
        HStack(spacing: 8) {
            mark(look, kind)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(run.name)
                        .themeFont(
                            look == .journal ? .display : .body, size: look == .journal ? 14 : 12,
                            weight: look == .console ? .regular : .semibold
                        )
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(kind == .running ? "now" : run.clock)
                        .themeFont(.body, size: 10)
                        .monospacedDigit()
                        .opacity(0.6)
                }
                HStack(spacing: 4) {
                    word(look, kind).lineLimit(1).layoutPriority(1)
                    Group {
                        if kind == .running {
                            Text(run.started, style: .timer)
                        } else {
                            Text(run.detail)
                        }
                    }
                    .themeFont(.body, size: 11)
                    .monospacedDigit()
                    .opacity(0.62)
                    .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func word(_ look: ShortcutsLook, _ kind: RunKind) -> some View {
        switch look {
        case .glass:
            Text(kind.word).themeFont(.body, size: 11, weight: .semibold).foregroundStyle(kind.hue(theme))
        case .journal:
            // Slanted like an italic: the bundled display faces have no italic to pick.
            Text(kind.word).themeFont(.display, size: 12.5, weight: .medium)
                .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.2, d: 1, tx: 2, ty: 0))
                .foregroundStyle(kind.hue(theme))
        case .console:
            Text(kind.word).themeFont(.body, size: 11, weight: kind == .failed ? .bold : .regular)
        }
    }

    @ViewBuilder private func mark(_ look: ShortcutsLook, _ kind: RunKind) -> some View {
        if look == .console {
            Text(kind.tag)
                .themeFont(.body, size: 9.5, weight: .bold)
                .frame(width: 30, height: 16)
                .background { if kind == .failed { Rectangle().fill(.themeAccent) } }
                .foregroundStyle(kind == .failed ? .themeOnAccent : .themeInk)
        } else {
            let hue = kind.hue(theme)
            ZStack {
                if look == .glass {
                    Circle().fill(hue.opacity(0.16))
                } else {
                    Circle().strokeBorder(hue, lineWidth: 1)
                }
                if kind == .running {
                    Spinner().padding(5)
                } else {
                    ThemeSymbol(kind.symbol).themeFont(.body, size: 10, weight: .bold)
                }
            }
            .frame(width: 22, height: 22)
            .foregroundStyle(hue)
        }
    }

    @ViewBuilder private var action: some View {
        switch run.outcome {
        case .running:
            Button {
                shortcuts.stop(run.id)
            } label: {
                ThemeSymbol("stop.fill").themeFont(.body, size: 8)
                    .frame(width: 22, height: 22)
                    .themePlatter(0.12, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop")
            .accessibilityLabel("Stop \(run.name)")
        case .failed:
            Button {
                shortcuts.run(run.name)
            } label: {
                Text("Retry")
                    .themeFont(.body, size: 10, weight: .semibold)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .themePlatter(0.12, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(shortcuts.running.contains(run.name))
            .accessibilityLabel("Retry \(run.name)")
        case .done, .stopped:
            EmptyView()
        }
    }

    @ViewBuilder private func runningBacking(_ look: ShortcutsLook, hue: Color) -> some View {
        switch look {
        case .glass: RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hue.opacity(0.1))
        case .journal: Rectangle().fill(.themeInk.opacity(0.04))
        case .console: Rectangle().fill(.themeInk).frame(width: 2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A ring turning once a second while a run goes on; with Reduce Motion it holds still.
private struct Spinner: View {
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

/// A line across the bottom of its frame, for a journal's ruled rows.
private struct Rule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// A shortcut in the full list: click to run it, right-click to pin or unpin it.
private struct ListRow: View {
    let name: String
    let shortcuts: ShortcutsFeature
    /// Called once it's started, to show the log.
    let ran: () -> Void
    @State private var hovering = false

    var body: some View {
        let running = shortcuts.running.contains(name)
        let favorite = shortcuts.favorites.contains(name)
        Button {
            shortcuts.run(name)
            ran()
        } label: {
            HStack(spacing: 6) {
                if running {
                    Spinner().frame(width: 10, height: 10)
                } else {
                    ThemeSymbol("play.fill").themeFont(.body, size: 9).opacity(0.7)
                }
                Text(name).themeFont(.body, size: 12, weight: .medium).lineLimit(1)
                Spacer(minLength: 0)
                if favorite { ThemeSymbol("pin.fill").themeFont(.body, size: 9).opacity(0.5) }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .themePlatter(hovering ? 0.1 : 0, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(running)
        .onHover { hovering = $0 }
        .contextMenu {
            if favorite {
                Button("Unpin from Favorites") { shortcuts.unpin(name) }
            } else {
                Button("Pin to Favorites") { shortcuts.pin(name) }
                    .disabled(shortcuts.favorites.count >= ShortcutsFeature.favoriteCount)
            }
        }
        .accessibilityLabel(running ? "\(name), running" : "Run \(name)")
    }
}

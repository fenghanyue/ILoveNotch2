// SPDX-License-Identifier: MIT
import AppKit
import NotchFeatures
import NotchTheme
import SwiftUI

/// The Agents tab: a timeline of what the connected tools' agents did, newest first (started, asked,
/// finished), filtered to who needs you or to one tool, every row a way back to its terminal. An ask
/// still waiting is lit orange in every theme, without pulsing. The hooks only report, so it offers
/// its terminal, where it's answered, rather than Allow and Deny. Each theme reads its own way
/// (`Look`), and the times move on once a minute.
struct AgentsView: View {
    let agents: AgentsFeature

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter = Filter.all

    enum Filter: Hashable {
        case all, needsYou
        case tool(AgentTool)
    }

    /// How the timeline reads: a `tail -f` log with tags and clock times where the theme draws a
    /// terminal, a diary with times along a margin line on a light sheet, lit dots on a rail otherwise.
    enum Look {
        case dots, diary, log
    }

    private var look: Look {
        if theme.skin(.tabRow) == "terminal" { return .log }
        return theme.appearance == .light ? .diary : .dots
    }

    var body: some View {
        if agents.connected.isEmpty {
            setup
        } else if agents.events.isEmpty {
            FeatureUnavailableView(
                symbol: "terminal", title: "No agents at work",
                message: "What \(names(agents.connected)) does shows up here, newest first.")
        } else {
            // Narrower than the default notch, rows drop the agent.
            GeometryReader { proxy in
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    feed(now: context.date, narrow: proxy.size.width < 380)
                }
            }
        }
    }

    private var setup: some View {
        VStack(spacing: 8) {
            FeatureUnavailableView(
                symbol: "terminal", title: "Your coding agents, in the notch",
                message: agents.available.isEmpty
                    ? "Install Claude Code or Codex, then connect it here."
                    : "The notch shows when an agent needs your approval or finishes, and takes you back to its "
                        + "terminal. Connecting adds a hook to the tool's own settings.")
            HStack(spacing: 8) {
                ForEach(agents.available) { tool in
                    Button("Connect \(tool.name)") { agents.connect(tool) }
                        .buttonStyle(.plain)
                        .themeFont(.body, .caption, weight: .semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .themePlatter(0.15, in: Capsule())
                }
            }
            if let failure = agents.failure {
                Text(failure).themeFont(.body, .caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Feed

    private func feed(now: Date, narrow: Bool) -> some View {
        let shown = agents.events.filter(shows)
        return VStack(spacing: 6) {
            filterBar(now: now)
            if shown.isEmpty {
                Text(look == .log ? "# nothing here" : filter == .needsYou ? "Nothing needs you" : "Nothing yet")
                    .themeFont(look == .log ? .mono : .body, .caption)
                    .foregroundStyle(.themeSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { event in
                            row(event, now: now, narrow: narrow)
                                .transition(reduceMotion ? .opacity : .push(from: .top))
                        }
                    }
                    .background(alignment: .topLeading) { rail }
                    .animation(.easeOut(duration: 0.2), value: shown.first?.id)
                    .padding(.vertical, 4)  // clear of the fading edges
                }
                .scrollIndicators(.never)
                .fadingEdges(length: 6)
            }
        }
    }

    private func shows(_ event: AgentEvent) -> Bool {
        switch filter {
        case .all: true
        case .needsYou: agents.needsYou(event)
        case .tool(let tool): event.tool == tool
        }
    }

    /// All and Needs you, then a filter per tool when more than one is connected; the date on the
    /// right, shorter or gone where it doesn't fit.
    private func filterBar(now: Date) -> some View {
        let tools = AgentTool.allCases.filter(agents.connected.contains)
        let filters = [Filter.all, .needsYou] + (tools.count > 1 ? tools.map(Filter.tool) : [])
        let waiting = agents.events.count(where: agents.needsYou)
        return HStack(spacing: 4) {
            ForEach(filters, id: \.self) { option in
                let lit = filter == option
                Button {
                    filter = option
                } label: {
                    Text(label(option, waiting: waiting))
                        .themeFont(look == .log ? .mono : .body, size: 11.5, weight: .semibold)
                        .themeSelectionInk(lit)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background {
                            if lit { SelectionMark(in: Capsule()) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityAddTraits(lit ? .isSelected : [])
            }
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                dateLabel(now: now, short: false)
                dateLabel(now: now, short: true)
                Color.clear.frame(width: 0, height: 0)
            }
            .foregroundStyle(.themeSecondary)
        }
        .frame(height: 26)
    }

    private func label(_ filter: Filter, waiting: Int) -> String {
        switch (filter, look) {
        case (.all, .log): "all"
        case (.all, _): "All"
        case (.needsYou, .log): "waiting:\(waiting)"
        case (.needsYou, _): waiting > 0 ? "Needs you · \(waiting)" : "Needs you"
        case (.tool(let tool), .log): tool.rawValue
        case (.tool(let tool), _): tool.name
        }
    }

    /// Black counts the day's events, Paper dates the page, and Terminal names the command.
    @ViewBuilder private func dateLabel(now: Date, short: Bool) -> some View {
        switch look {
        case .log:
            Text(short ? "tail -f" : "tail -f · today").themeFont(.mono, size: 11).fixedSize()
        case .diary:
            let long = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
            let brief = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            Text(now.formatted(short ? brief : long))
                .themeFont(.display, size: 14)
                .italic()
                .fixedSize()
        case .dots:
            let count = agents.events.count
            let today = agents.events.last.map { Calendar.current.isDate($0.time, inSameDayAs: now) } ?? true
            Text((today && !short ? "Today · " : "") + (count == 1 ? "1 event" : "\(count) events"))
                .themeFont(.body, size: 11, weight: .medium)
                .fixedSize()
        }
    }

    /// The line through the rows' markers: faint ink under Black's dots, the diary's margin line in
    /// the ask's red, none in a log.
    @ViewBuilder private var rail: some View {
        if look != .log {
            Rectangle()
                .fill(look == .diary ? color(.asked).opacity(0.55) : theme.color(.ink).opacity(0.2))
                .frame(width: 1)
                .padding(.vertical, FeedRow.height / 2)
                .padding(.leading, FeedRow.markerCenter(look) - 0.5)
                .accessibilityHidden(true)
        }
    }

    private func row(_ event: AgentEvent, now: Date, narrow: Bool) -> some View {
        let session = agents.sessions.first { $0.id == event.session }
        return FeedRow(
            event: event, look: look, pending: agents.needsYou(event), tint: color(event.kind), ask: color(.asked),
            time: time(event, now: now), narrow: narrow, open: { agents.open(event) },
            clear: session.map { session in { agents.clear(session) } })
    }

    /// Each kind's color: started in the accent; finished in green, or the ink where the accent is
    /// the ink (Terminal's phosphor); an ask in orange in every theme, as it's always been. On a light
    /// sheet the system's green and orange are deepened toward the ink, to read as text.
    private func color(_ kind: AgentEvent.Kind) -> Color {
        switch kind {
        case .started: theme.color(.accent)
        case .finished:
            theme.colors.ink.text == theme.colors.accent.text ? theme.color(.ink) : legible(.systemGreen)
        case .asked: legible(.systemOrange)
        }
    }

    private func legible(_ color: NSColor) -> Color {
        guard theme.appearance == .light else { return Color(nsColor: color) }
        return Color(nsColor: color.blended(withFraction: 0.4, of: NSColor(theme.color(.ink))) ?? color)
    }

    /// How long ago, "2m" or the diary's "2 min", fixed when drawn and redrawn each minute; the
    /// clock time in a log.
    private func time(_ event: AgentEvent, now: Date) -> String {
        if look == .log { return event.time.formatted(Self.clock) }
        let minutes = Int(now.timeIntervalSince(event.time) / 60)
        guard minutes > 0 else { return "now" }
        return Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: look == .diary ? .abbreviated : .narrow, maximumUnitCount: 1))
    }

    /// "14:32", as a log writes it whatever the locale.
    private static let clock = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: .current, calendar: .current)
}

/// One event: when, its marker (a lit dot, or a tag in a log), the project, what happened, and which
/// agent, with a way to its terminal. A click anywhere on it goes there too.
private struct FeedRow: View {
    let event: AgentEvent
    let look: AgentsView.Look
    /// An ask still waiting: lit in `ask`, and its terminal offered in words.
    let pending: Bool
    /// The kind's color.
    let tint: Color
    let ask: Color
    let time: String
    /// Leaves out the agent, for the narrowest notch.
    let narrow: Bool
    let open: () -> Void
    /// Forgets the session, while there is one.
    let clear: (() -> Void)?

    @Environment(\.theme) private var theme
    @State private var hovering = false

    static let height: CGFloat = 30
    static let marker: CGFloat = 18
    static let spacing: CGFloat = 8
    static let leading: CGFloat = 6

    /// The diary's times are words in a serif: "11 min".
    static func timeWidth(_ look: AgentsView.Look) -> CGFloat { look == .diary ? 48 : 40 }

    /// Where the rail runs, through the markers.
    static func markerCenter(_ look: AgentsView.Look) -> CGFloat {
        leading + timeWidth(look) + spacing + marker / 2
    }

    private var role: Theme.Fonts.Role { look == .log ? .mono : .body }

    private var radius: CGFloat? { theme.controls?.radius.map { CGFloat($0) } }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? 10, style: .continuous)
        HStack(spacing: Self.spacing) {
            timeLabel
                .foregroundStyle(pending ? ask : theme.color(.secondary))
                .lineLimit(1)
                .frame(width: Self.timeWidth(look), alignment: .trailing)
            marker
            Text(event.project)
                .themeFont(look == .log ? .mono : .display, size: projectSize, weight: .semibold)
                .lineLimit(1)
                .frame(width: 76, alignment: .leading)
            what
                .themeFont(role, size: 12)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !narrow, !pending {
                Text(look == .log ? event.tool.rawValue : event.tool.shortName)
                    .themeFont(role, size: 11)
                    .foregroundStyle(.themeSecondary)
                    .lineLimit(1)
                    .frame(width: 40, alignment: .leading)
            }
            trailing
        }
        .padding(.leading, Self.leading)
        .padding(.trailing, 4)
        .frame(height: Self.height)
        .background {
            if pending {
                shape.fill(ask.opacity(0.12))
                shape.strokeBorder(ask.opacity(0.4), lineWidth: 1)
            }
        }
        .themePlatter(hovering && !pending ? 0.06 : 0, in: shape)
        .contentShape(shape)
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help(event.app == nil ? "" : pending ? "Answer it in its terminal" : "Go to its terminal")
        .contextMenu {
            Button("Go to Terminal", action: open).disabled(event.app == nil)
            if let clear { Button("Clear", action: clear) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityAction(named: "Clear") { clear?() }
    }

    private var projectSize: CGFloat {
        switch look {
        case .dots: 13
        case .diary: 15
        case .log: 12
        }
    }

    @ViewBuilder private var timeLabel: some View {
        switch look {
        case .diary: Text(time).themeFont(.display, size: 13).italic()
        case .dots, .log: Text(time).themeFont(role, size: 11).monospacedDigit()
        }
    }

    /// A lit dot with the kind's icon on the rail, an outlined one on paper, or a tag in a log.
    @ViewBuilder private var marker: some View {
        switch look {
        case .log:
            Text(Self.tags[event.kind] ?? "")
                .themeFont(.mono, size: 12, weight: .bold)
                .foregroundStyle(tint)
        case .dots, .diary:
            ThemeSymbol(Self.symbols[event.kind] ?? "circle")
                .themeFont(.body, size: 8, weight: .bold)
                .foregroundStyle(tint)
                .frame(width: Self.marker, height: Self.marker)
                .background {
                    // Opaque, so the rail stops at it.
                    Circle().fill(theme.surface.color.color)
                    if look == .dots {
                        Circle().fill(tint.opacity(0.2))
                            .shadow(color: tint.opacity(pending ? 0.7 : 0.4), radius: pending ? 7 : 4)
                    } else {
                        Circle().strokeBorder(tint, lineWidth: 1.2)
                    }
                }
        }
    }

    private static let symbols: [AgentEvent.Kind: String] = [
        .started: "play.fill", .asked: "exclamationmark", .finished: "checkmark",
    ]
    private static let tags: [AgentEvent.Kind: String] = [.started: "[RUN ]", .asked: "[ASK ]", .finished: "[DONE]"]

    /// What happened, its verb in the kind's color: "Started working", "Wants to use Bash", "Finished
    /// after 11 min"; a log's lower-case "use Bash?" and "finished in 11m".
    private var what: Text {
        let (verb, rest) = words
        return Text("\(Text(verb).fontWeight(.semibold).foregroundStyle(tint))\(rest)")
    }

    private var words: (verb: String, rest: String) {
        let request = event.request
        switch (event.kind, look) {
        case (.started, .log): return ("", "started")
        case (.started, _): return ("Started", " working")
        case (.asked, .log):
            if pending { return (request ?? event.detail ?? "approval", "?") }
            return ("", request.map { "asked to \($0)" } ?? event.detail.map { "asked: \($0)" } ?? "asked")
        case (.asked, _):
            if let request { return (pending ? "Wants to" : "Asked to", " \(request)") }
            return (pending ? "Asks" : "Asked", event.detail.map { ": \($0)" } ?? " for approval")
        case (.finished, .log): return ("", "finished" + (took(.narrow).map { " in \($0)" } ?? ""))
        case (.finished, _): return ("Finished", took(.abbreviated).map { " after \($0)" } ?? "")
        }
    }

    private func took(_ width: Duration.UnitsFormatStyle.UnitWidth) -> String? {
        event.took.map {
            Duration.seconds(max($0, 1)).formatted(
                .units(allowed: [.hours, .minutes, .seconds], width: width, maximumUnitCount: 1))
        }
    }

    /// The terminal, offered in words for a waiting ask (the notch can't answer it), else an arrow.
    /// The narrowest notch says just "Open", to leave the ask room.
    @ViewBuilder private var trailing: some View {
        if event.app == nil {
            Color.clear.frame(width: 24, height: 22)
        } else if pending {
            let shape = radius.map { AnyShape(RoundedRectangle(cornerRadius: $0)) } ?? AnyShape(Capsule())
            Button(action: open) {
                Text(look == .log ? "[open]" : narrow ? "Open" : "Open Terminal")
                    .themeFont(role, size: 11, weight: .semibold)
                    .foregroundStyle(theme.surface.color.color)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(ask, in: shape)
                    .fixedSize()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Answer it in its terminal")
        } else {
            Button(action: open) {
                ThemeSymbol("arrow.up.right")
                    .themeFont(.body, size: 10, weight: .semibold)
                    .foregroundStyle(.themeSecondary)
                    .frame(width: 24, height: 22)
                    .themePlatter(0.08, in: Capsule())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Go to its terminal")
            .accessibilityLabel("Open \(event.project)'s terminal")
        }
    }
}

/// "Claude Code and Codex".
private func names(_ tools: Set<AgentTool>) -> String {
    AgentTool.allCases.filter(tools.contains).map(\.name).formatted(.list(type: .and))
}

extension AgentsFeature {
    /// Settings › Agents: which tools report to the notch.
    public var settingsView: some View { AgentsSettings(agents: self) }
}

private struct AgentsSettings: View {
    @Bindable var agents: AgentsFeature

    var body: some View {
        Group {
            ForEach(AgentTool.allCases) { tool in
                // A closure, not a method reference: see the app's GeneralSettings.
                Toggle(
                    isOn: Binding(
                        get: { agents.connected.contains(tool) },
                        set: { $0 ? agents.connect(tool) : agents.disconnect(tool) })
                ) {
                    HStack(spacing: 6) {
                        ProviderLogo(providerID: tool.rawValue, name: tool.name, size: 14)
                        Text(tool.name)
                    }
                    Text(explanation(tool))
                }
                .disabled(!agents.available.contains(tool))
            }
            Toggle("Show when an agent finishes in the background", isOn: $agents.announcesDone)
            if let failure = agents.failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear(perform: agents.refreshConnected)
    }

    private func explanation(_ tool: AgentTool) -> String {
        guard agents.available.contains(tool) else { return "Not on this Mac." }
        let adds = "Adds hooks to ~/\(tool.configPath); turning this off removes them."
        return tool == .codex ? adds + " Codex asks you to trust them the next time it starts." : adds
    }
}

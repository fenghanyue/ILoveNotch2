// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchTheme
import SwiftUI

/// The Home tab. It does no work of its own: while it's open, the tabs it glances at run in full
/// (`FeatureID.onHome`).
@MainActor
@Observable
public final class HomeFeature: NotchFeature {
    public let id = FeatureID.home
    public var phase: FeaturePhase = .stopped

    public init() {}
}

/// A bento of cards, each sized by what it holds: the song big, with its cover and controls; the next
/// event wide, with Join; the tasks tall, ticked off in place; the AI plans' ring and a running timer
/// small; and the script along the bottom, with Start. A click on a card opens its tab, and its
/// buttons act in place. A tab that's off drops its card, and its neighbors take the room. A short
/// notch lines the cards up in rows instead, scrolling.
public struct HomeView: View {
    let media: MediaFeature
    let calendar: CalendarFeature
    let tasks: TasksFeature
    let timer: TimerFeature
    let prompter: PrompterFeature
    /// The AI plans' card, from the GitHub build's AI Usage; nil leaves it out.
    let usage: AnyView?
    /// The tabs that are on.
    let tabs: Set<FeatureID>
    let open: (FeatureID) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The cards rise into place once the tab is open.
    @State private var appeared = false

    public init(
        media: MediaFeature, calendar: CalendarFeature, tasks: TasksFeature, timer: TimerFeature,
        prompter: PrompterFeature, usage: AnyView?, tabs: Set<FeatureID>, open: @escaping (FeatureID) -> Void
    ) {
        self.media = media
        self.calendar = calendar
        self.tasks = tasks
        self.timer = timer
        self.prompter = prompter
        self.usage = usage
        self.tabs = tabs
        self.open = open
    }

    private enum Card: CaseIterable {
        case music, event, tasks, usage, timer, script

        var feature: FeatureID {
            switch self {
            case .music: .media
            case .event: .calendar
            case .tasks: .tasks
            case .usage: .usage
            case .timer: .timer
            case .script: .prompter
            }
        }
    }

    private static let gap: CGFloat = 8
    /// Shorter than this, the cards line up in rows.
    private static let bentoHeight: CGFloat = 150

    public var body: some View {
        let shown = Card.allCases.filter(isShown)
        GeometryReader { proxy in
            if shown.isEmpty {
                Text("Turn on a tab in Settings to see it here")
                    .themeFont(.body, size: 12)
                    .foregroundStyle(.themeInk.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if proxy.size.height < Self.bentoHeight {
                rows(shown, in: proxy.size)
            } else {
                bento(shown, in: proxy.size)
            }
        }
        .onAppear { appeared = true }
    }

    private func isShown(_ card: Card) -> Bool {
        switch card {
        case .usage: usage != nil
        case .timer: tabs.contains(.timer) && (timer.countdown != nil || timer.stopwatch.isRunning)
        default: tabs.contains(card.feature)
        }
    }

    // MARK: Layout

    /// Four columns and three rows: the song over the script on the left; on the right the event,
    /// then the tasks beside the small cards.
    private func bento(_ shown: [Card], in size: CGSize) -> some View {
        let gap = Self.gap
        let row = (size.height - 2 * gap) / 3
        let has = Set(shown)
        let left = has.contains(.music) || has.contains(.script)
        let small = has.contains(.usage) || has.contains(.timer)
        let lower = has.contains(.tasks) || small
        // Half, as in the mock, once each small column gets about 116 pt; narrower, the song gives way.
        let rightWidth = left ? max((size.width - gap) / 2, min(240, size.width * 0.58)) : size.width
        return HStack(spacing: gap) {
            if left {
                VStack(spacing: gap) {
                    if has.contains(.music) { tile(.music, in: shown) }
                    if has.contains(.script) {
                        tile(.script, in: shown).frame(height: has.contains(.music) ? row : nil)
                    }
                }
            }
            if has.contains(.event) || lower {
                VStack(spacing: gap) {
                    if has.contains(.event) { tile(.event, in: shown).frame(height: lower ? row : nil) }
                    if lower {
                        HStack(spacing: gap) {
                            if has.contains(.tasks) {
                                tile(.tasks, in: shown).frame(width: small ? (rightWidth - gap) / 2 : nil)
                            }
                            if small {
                                VStack(spacing: gap) {
                                    if has.contains(.usage) { tile(.usage, in: shown) }
                                    if has.contains(.timer) { tile(.timer, in: shown) }
                                }
                            }
                        }
                    }
                }
                .frame(width: rightWidth)
            }
        }
    }

    /// Two cards a row (three in a wide notch), two rows in view, each card down to its one line.
    private func rows(_ shown: [Card], in size: CGSize) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: size.width >= 560 ? 3 : 2)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: Self.gap) {
                ForEach(shown, id: \.self) { card in
                    tile(card, in: shown).frame(height: max(46, (size.height - Self.gap) / 2))
                }
            }
        }
        .fadingEdges()
    }

    /// A card: its backing (the theme's card color in turn, or its platter), a glow in what it shows
    /// in a dark theme, and its content. A click anywhere opens its tab.
    private func tile(_ card: Card, in shown: [Card]) -> some View {
        let index = shown.firstIndex(of: card) ?? 0
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let title = card.feature.title
        // Erased, or six tiles each carrying every card's type overflow the stack in a debug build.
        return AnyView(content(card))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background { glow(card).clipShape(shape) }
            .background { backing(index, in: shape) }
            .foregroundStyle(ink)
            .contentShape(shape)
            .onTapGesture { open(card.feature) }
            .help("Open \(title)")
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityAction(named: "Open \(title)") { open(card.feature) }
            // Each rises 6 pt and fades in, 30 ms after the one before; with Reduce Motion they're
            // just there.
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 6)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22).delay(Double(index) * 0.03), value: appeared)
    }

    @ViewBuilder private func content(_ card: Card) -> some View {
        switch card {
        case .music: music
        case .event: event
        case .tasks: taskList
        case .usage: if let usage { usageCard(usage) }
        case .timer: timerCard
        case .script: script
        }
    }

    @ViewBuilder private func backing(_ index: Int, in shape: RoundedRectangle) -> some View {
        if let cards = theme.cards, !cards.colors.isEmpty {
            shape.fill(cards.colors[index % cards.colors.count].color)
        } else {
            // On a light sheet a card covers its texture in the sheet's own color, like an index card
            // on the page, outlined, with a soft print shadow unless the theme draws a hard one.
            let light = theme.appearance == .light
            Color.clear
                .themePlatter(light ? 0.01 : 0.07, in: shape)
                .background {
                    if light {
                        if theme.controls?.shadow != .hard { shape.fill(ink.opacity(0.07)).offset(x: 3, y: 3) }
                        shape.fill(theme.surface.color.color)
                    }
                }
        }
    }

    /// Dark sheets light the song's card in its cover's color, the event's in its calendar's, and a
    /// running timer's in the accent.
    @ViewBuilder private func glow(_ card: Card) -> some View {
        if glows, let spot = glowSpot(card) {
            RadialGradient(
                colors: [spot.color.opacity(0.3), .clear], center: spot.center, startRadius: 0, endRadius: 150)
        }
    }

    private func glowSpot(_ card: Card) -> (color: Color, center: UnitPoint)? {
        let color: Color? =
            switch card {
            case .music: media.nowPlaying == nil ? nil : media.accent?.color
            case .event: nextEvent.map { $0.color?.color ?? theme.color(.accent) }
            case .timer: theme.color(.accent)
            default: nil
            }
        let center: UnitPoint = card == .music ? .init(x: 0.16, y: 0.42) : card == .event ? .trailing : .bottomLeading
        return color.map { ($0, center) }
    }

    // MARK: Theme

    /// What's written on a card: the ink of the theme's card colors, or its own.
    private var ink: Color { theme.cards?.ink.color ?? theme.color(.ink) }
    private var secondary: Color { ink.opacity(0.62) }
    private var radius: CGFloat { theme.controls?.radius.map { CGFloat($0) } ?? 16 }
    /// Outlined themes label their cards in small capitals.
    private var caps: Bool { theme.controls?.style == .outline }
    private var square: Bool { theme.controls?.radius == 0 }
    private var glows: Bool {
        theme.appearance == .dark && theme.cards == nil && theme.controls?.style != .outline && !reduceTransparency
    }
    /// Join's and play's colors: the ink with the sheet's color on it where the theme has no controls
    /// of its own (Black's white button), else the accent and its ink.
    private var primary: (fill: Color, ink: Color) {
        theme.controls == nil ? (ink, theme.surface.color.color) : (theme.color(.accent), theme.color(.onAccent))
    }
    private var controlShape: AnyShape {
        theme.controls?.radius.map { AnyShape(RoundedRectangle(cornerRadius: $0, style: .continuous)) }
            ?? AnyShape(Capsule())
    }
    /// The song's color: the cover's, or the theme's when its seek bar says so.
    private var musicTint: Color { theme.color(theme.seekBar.fill, artwork: media.accent?.color) }

    // MARK: Parts

    /// The card's name, a button to its tab, and what it says at a glance on the right. When both
    /// don't fit, the name stays whole and the glance goes: "Tasks ›" rather than "TAS… 3 due".
    private func header(_ feature: FeatureID, detail: String? = nil, tint: Color? = nil) -> some View {
        ViewThatFits(in: .horizontal) {
            headerRow(feature, detail: detail, tint: tint)
            headerRow(feature, detail: nil, tint: tint)
        }
    }

    private func headerRow(_ feature: FeatureID, detail: String?, tint: Color?) -> some View {
        HStack(spacing: 6) {
            Button {
                open(feature)
            } label: {
                HStack(spacing: 2) {
                    Text(feature.title)
                    ThemeSymbol("chevron.right").imageScale(.small)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .themeFont(.body, size: caps ? 10 : 11, weight: .semibold)
            .textCase(caps ? .uppercase : nil)
            .tracking(caps ? 1 : 0)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .themeFont(.body, size: 10, weight: tint == nil ? .regular : .semibold)
                    .foregroundStyle(tint ?? secondary)
            }
        }
        .foregroundStyle(secondary)
        .lineLimit(1)
    }

    /// A card with nothing to show but a line saying so.
    private func notice(_ feature: FeatureID, _ text: String) -> some View {
        let line = Text(text).themeFont(.body, size: 12).foregroundStyle(secondary).lineLimit(2)
        return ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 6) {
                header(feature)
                line
            }
            line
        }
    }

    private func bar(_ fraction: Double, tint: Color, height: CGFloat = 4) -> some View {
        let shape = RoundedRectangle(cornerRadius: square ? 0 : height / 2)
        return shape.fill(ink.opacity(0.16))
            .overlay {
                shape.fill(tint)
                    .scaleEffect(x: min(max(fraction, 0), 1), y: 1, anchor: .leading)
                    .shadow(color: glows ? tint.opacity(0.6) : .clear, radius: 4)
            }
            .frame(minWidth: 40, maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
    }

    // MARK: Music

    /// Shorter cards shrink the cover and drop the card's name; the shortest is one row.
    @ViewBuilder private var music: some View {
        if let now = media.nowPlaying {
            ViewThatFits(in: .vertical) {
                musicStack(now, cover: 72, header: true)
                musicStack(now, cover: 56, header: true)
                musicStack(now, cover: 56, header: false)
                musicStack(now, cover: 44, header: false)
                musicRow(now)
            }
        } else {
            notice(.media, "Nothing playing")
        }
    }

    private func musicStack(_ now: NowPlaying, cover size: CGFloat, header: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if header { self.header(.media, detail: playerName(now)) }
            HStack(spacing: 12) {
                cover(size)
                VStack(alignment: .leading, spacing: 3) {
                    Text(now.title).themeFont(.display, size: size >= 56 ? 19 : 15, weight: .semibold)
                    if let line = trackLine(now) {
                        Text(line).themeFont(.body, size: 12).foregroundStyle(secondary)
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            musicControls(now)
        }
    }

    private func musicRow(_ now: NowPlaying) -> some View {
        HStack(spacing: 10) {
            cover(30)
            VStack(alignment: .leading, spacing: 1) {
                Text(now.title).themeFont(.display, size: 13, weight: .semibold)
                if let artist = now.artist {
                    Text(artist).themeFont(.body, size: 11).foregroundStyle(secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            playButton(now, size: 26)
                .buttonStyle(PressableButtonStyle())
                .disabled(!media.hasControls)
        }
    }

    private func trackLine(_ now: NowPlaying) -> String? {
        let line = [now.artist, now.album].compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// The app it plays in.
    private func playerName(_ now: NowPlaying) -> String? {
        guard let id = now.appBundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return nil }
        return FileManager.default.displayName(atPath: app.path).replacing(".app", with: "")
    }

    /// Outlined themes frame the cover like a print; dark ones light it in its color.
    private func cover(_ size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(radius, size * 0.2), style: .continuous)
        return ZStack {
            if let artwork = media.artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
            } else {
                shape.fill(musicTint.opacity(0.3))
                ThemeSymbol("music.note").themeFont(.body, size: size * 0.36)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            if caps { shape.stroke(theme.controls?.lineColor?.color ?? ink.opacity(0.4), lineWidth: 1) }
        }
        .shadow(color: glows ? musicTint.opacity(0.45) : .clear, radius: size * 0.16, y: size * 0.06)
        .accessibilityHidden(true)
    }

    /// Back, play or pause, and ahead (by 15 seconds where the player skips that way), then how far in.
    private func musicControls(_ now: NowPlaying) -> some View {
        let interval = now.skipsByInterval
        return HStack(spacing: 4) {
            Button {
                media.send(interval ? .skipBackward : .previousTrack)
            } label: {
                ThemeSymbol(interval ? "gobackward.15" : "backward.fill").frame(width: 24, height: 26)
            }
            .accessibilityLabel(interval ? "Back 15 seconds" : "Previous track")
            playButton(now, size: 30)
            Button {
                media.send(interval ? .skipForward : .nextTrack)
            } label: {
                ThemeSymbol(interval ? "goforward.15" : "forward.fill").frame(width: 24, height: 26)
            }
            .accessibilityLabel(interval ? "Forward 15 seconds" : "Next track")
            progress(now).padding(.leading, 6)
        }
        .themeFont(.body, size: 13)
        .buttonStyle(PressableButtonStyle())
        .disabled(!media.hasControls)
    }

    /// An ink disc, or the accent on themes with controls of their own; a ring on a light sheet.
    private func playButton(_ now: NowPlaying, size: CGFloat) -> some View {
        let disc = square ? AnyShape(Rectangle()) : AnyShape(Circle())
        let light = theme.appearance == .light
        return Button {
            media.send(.togglePlayPause)
        } label: {
            ThemeSymbol(now.isPlaying ? "pause.fill" : "play.fill")
                .themeFont(.body, size: size * 0.4, weight: .bold)
                .foregroundStyle(light ? ink : primary.ink)
                .frame(width: size, height: size)
                .background {
                    if light { disc.stroke(ink, lineWidth: 1.5) } else { disc.fill(primary.fill) }
                }
                .contentShape(disc)
        }
        .accessibilityLabel(now.isPlaying ? "Pause" : "Play")
    }

    /// The time in and left around a bar, or the bar alone when narrow. Once a second while playing.
    @ViewBuilder private func progress(_ now: NowPlaying) -> some View {
        if let duration = now.duration, duration > 0 {
            TimelineView(.periodic(from: .now, by: now.isPlaying ? 1 : 3600)) { context in
                let position = min(max(now.position(at: context.date) ?? 0, 0), duration)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(formatTime(position, roundingUp: false))
                        bar(position / duration, tint: musicTint)
                        Text("-" + formatTime(duration - position, roundingUp: false))
                    }
                    bar(position / duration, tint: musicTint)
                }
                .themeFont(.body, size: 10)
                .monospacedDigit()
                .foregroundStyle(secondary)
            }
        } else {
            Spacer(minLength: 0)
        }
    }

    // MARK: Calendar

    /// The next event still to come today, whichever day the Calendar tab shows.
    private var nextEvent: DayEvent? {
        calendar.events(on: Calendar.current.startOfDay(for: .now)).first { !$0.isAllDay && $0.end > .now }
    }

    @ViewBuilder private var event: some View {
        if calendar.access != .granted {
            notice(.calendar, "Allow access in the Calendar tab")
        } else if let next = nextEvent {
            // "in 18 min" moves on once a minute.
            TimelineView(.everyMinute) { _ in
                let when = Self.when(next, now: .now)
                let tint = eventTint(next)
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        header(.calendar, detail: when, tint: tint)
                        eventRow(next, title: 16) {
                            Text(eventLine(next)).themeFont(.body, size: 11).foregroundStyle(secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        header(.calendar, detail: when, tint: tint)
                        eventRow(next, title: 15) { EmptyView() }
                    }
                    eventRow(next, title: 13) {
                        Text(when).themeFont(.body, size: 11, weight: .semibold).foregroundStyle(tint)
                    }
                }
            }
        } else {
            notice(.calendar, "Nothing else today")
        }
    }

    /// The title and a line under it beside Join, which says so where there's room.
    private func eventRow(_ event: DayEvent, title size: CGFloat, @ViewBuilder detail: () -> some View)
        -> some View
    {
        let words = VStack(alignment: .leading, spacing: 1) {
            Text(event.title).themeFont(.display, size: size, weight: .semibold)
            detail()
        }
        .lineLimit(1)
        let joins = event.meeting != nil && !event.isDeclined
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                words.frame(minWidth: 130, idealWidth: 130, maxWidth: .infinity, alignment: .leading)
                if joins { joinButton(event, labeled: true) }
            }
            HStack(spacing: 8) {
                words.frame(maxWidth: .infinity, alignment: .leading)
                if joins { joinButton(event, labeled: false) }
            }
        }
    }

    /// "in 18 min" in the calendar's color where cards glow, else in the accent, or the ink where the
    /// accent is a fill rather than a color for words (Brutal's yellow).
    private func eventTint(_ event: DayEvent) -> Color {
        if glows { return event.color?.color ?? theme.color(.accent) }
        return theme.selectsOnAccent ? ink : theme.color(.accent)
    }

    /// "11:00–11:30 · Google Meet", or where it is.
    private func eventLine(_ event: DayEvent) -> String {
        let times =
            event.start.formatted(date: .omitted, time: .shortened) + "–"
            + event.end.formatted(date: .omitted, time: .shortened)
        return [times, event.meeting?.service ?? event.place].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Now" once it's started, "in 18 min" within the hour, else when it starts.
    static func when(_ event: DayEvent, now: Date) -> String {
        guard event.start > now else { return "Now" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes < 60 ? "in \(minutes) min" : event.start.formatted(date: .omitted, time: .shortened)
    }

    private func joinButton(_ event: DayEvent, labeled: Bool) -> some View {
        Button {
            calendar.join(event)
        } label: {
            Group {
                if labeled { ThemeLabel("Join", symbol: "video.fill") } else { ThemeSymbol("video.fill") }
            }
            .themeFont(.body, size: 12, weight: .semibold)
            .foregroundStyle(primary.ink)
            .padding(.horizontal, labeled ? 12 : 9)
            .frame(height: 28)
            .background(primary.fill, in: controlShape)
            .contentShape(controlShape)
        }
        .buttonStyle(PressableButtonStyle())
        .help(event.meeting.map { "Join on \($0.service)" } ?? "Join")
        .accessibilityLabel("Join")
    }

    // MARK: Tasks

    /// As many tasks as fit, soonest due first, each ticked off in place.
    @ViewBuilder private var taskList: some View {
        if tasks.access != .granted {
            notice(.tasks, "Allow access in the Tasks tab")
        } else if tasks.tasks.isEmpty {
            notice(.tasks, "Nothing to do")
        } else {
            ViewThatFits(in: .vertical) {
                taskStack(5, header: true)
                taskStack(4, header: true)
                taskStack(3, header: true)
                taskStack(2, header: true)
                taskStack(1, header: true)
                taskStack(1, header: false)
            }
        }
    }

    private func taskStack(_ count: Int, header: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if header { self.header(.tasks, detail: dueSummary) }
            ForEach(tasks.tasks.prefix(count)) { taskRow($0) }
        }
    }

    /// "3 due" today or before, or how many are open.
    private var dueSummary: String {
        let now = Date.now
        let due = tasks.tasks.filter { $0.group(now: now) <= .today }.count
        return due > 0 ? "\(due) due" : "\(tasks.tasks.count) open"
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                    tasks.complete(task)
                }
            } label: {
                ThemeSymbol("circle").themeFont(.body, size: 13).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title).themeFont(.body, size: 12, weight: .medium)
                if let due = task.due {
                    Text(DueLabel.text(for: due, hasTime: task.hasTime))
                        .themeFont(.body, size: 10)
                        .foregroundStyle(task.isOverdue() ? Color.red : secondary)  // overdue: red in every theme
                }
            }
            .lineLimit(1)
        }
    }

    // MARK: AI Usage

    private func usageCard(_ usage: AnyView) -> some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 6) {
                header(.usage)
                usage
            }
            usage
        }
        .minimumScaleFactor(0.8)
    }

    // MARK: Timer

    /// What's left of the countdown, or the stopwatch's time, changing once a second without
    /// animating, and still while paused.
    private var timerCard: some View {
        let countdown = timer.countdown
        let running = countdown?.isRunning ?? timer.stopwatch.isRunning
        return TimelineView(.periodic(from: .now, by: running ? 1 : 3600)) { context in
            let seconds = countdown?.remaining(at: context.date) ?? timer.stopwatch.elapsed(at: context.date)
            let time = formatTime(seconds, roundingUp: countdown != nil)
            let done = countdown.map { $0.total > 0 ? 1 - seconds / $0.total : 0 }
            let stack = { (size: CGFloat, label: String?) in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        header(.timer)
                        timerButton(running)
                    }
                    timerDigits(time, size: size, running: running, label: label)
                    if let done { bar(done, tint: theme.color(.accent), height: 3) }
                }
            }
            // Narrower cards drop the word after the time, then shrink it; shorter ones are one row.
            ViewThatFits {
                stack(22, countdown == nil ? "elapsed" : "left")
                stack(22, nil)
                stack(18, nil)
                HStack(spacing: 6) {
                    timerDigits(time, size: 18, running: running, label: nil)
                    Spacer(minLength: 0)
                    timerButton(running)
                }
            }
        }
    }

    private func timerDigits(_ time: String, size: CGFloat, running: Bool, label: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(time)
                .themeFont(.numbers, size: size, weight: .semibold)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .opacity(running ? 1 : 0.5)
            if let label { Text(label).themeFont(.body, size: 10).foregroundStyle(secondary) }
        }
        .lineLimit(1)
    }

    private func timerButton(_ running: Bool) -> some View {
        Button {
            if timer.countdown != nil {
                running ? timer.pause() : timer.resume()
            } else {
                timer.toggleStopwatch()
            }
        } label: {
            ThemeSymbol(running ? "pause.fill" : "play.fill")
                .themeFont(.body, size: 9, weight: .bold)
                .frame(width: 22, height: 22)
                .modifier(CardChip(strength: 0.12, shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(running ? "Pause timer" : "Resume timer")
    }

    // MARK: Prompter

    /// The script's first lines, how long it takes to read, and Start, which opens the prompter on it.
    @ViewBuilder private var script: some View {
        let text = prompter.script.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            notice(.prompter, "No script yet")
        } else {
            let preview = String(text.prefix(400)).replacing(/\s+/, with: " ")
            let words = text.split(whereSeparator: \.isWhitespace).count
            let minutes = max(1, Int((Double(words) / PrompterFeature.wordsPerSecond / 60).rounded()))
            let lines = { (limit: Int) in Text(preview).themeFont(.display, size: 13).lineLimit(limit) }
            HStack(spacing: 10) {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        header(.prompter, detail: "\(minutes) min")
                        lines(8)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        header(.prompter, detail: "\(minutes) min")
                        lines(2)
                    }
                    lines(2)
                    lines(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                startButton
            }
        }
    }

    private var startButton: some View {
        Button {
            open(.prompter)
            prompter.start()
        } label: {
            HStack(spacing: 4) {
                ThemeSymbol("play.fill").imageScale(.small)
                Text(prompter.isReading ? "Resume" : "Start")
            }
            .themeFont(.body, size: 11, weight: .semibold)
            .foregroundStyle(secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .modifier(CardChip(strength: 0.1, shape: controlShape))
            .contentShape(controlShape)
        }
        .buttonStyle(PressableButtonStyle())
        .help("Read it in the prompter")
    }
}

/// A button's backing on a card: the theme's platter, or on a theme's card colors the card's ink
/// faintly, as the theme's own ink is for its sheet.
private struct CardChip<S: Shape>: ViewModifier {
    let strength: Double
    let shape: S
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        if let cards = theme.cards {
            content.background(cards.ink.color.opacity(strength), in: shape)
        } else {
            content.themePlatter(strength, in: shape)
        }
    }
}

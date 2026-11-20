// SPDX-License-Identifier: MIT
import NotchTheme
import SwiftUI

/// The calendar tab: the week across the top, a dot in its calendar's color for each of a day's
/// first four events, and the chosen day's events below as one-line rows. On today the finished
/// ones fold into "N earlier" and the next one is lit, with its countdown and Join. The day's tasks
/// and every overdue one sit beside them, on whichever day, and a click on one opens it in Tasks.
/// A field at the bottom adds an event from a line like "Lunch with Sam tomorrow 1pm" (a time alone
/// lands on the chosen day). Your own events can be edited in place or deleted from the notch. The
/// selection slides between days, the day cross-fades, and another week pushes in from its side;
/// with Reduce Motion each swaps at once.
struct CalendarView: View {
    let calendar: CalendarFeature
    @State private var draft = ""
    /// The event being edited in place.
    @State private var editing: DayEvent.ID?
    /// The task row under the pointer, lit to show a click opens it.
    @State private var hoveredTask: TaskItem.ID?
    /// Today's finished events, unfolded.
    @State private var showsEarlier = false
    /// Whether the week last moved ahead, so the next one pushes in from that side.
    @State private var forward = true
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    init(calendar: CalendarFeature, editing: DayEvent.ID? = nil) {
        self.calendar = calendar
        _editing = State(initialValue: editing)
    }

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85) }

    var body: some View {
        if calendar.access != .granted {
            EventAccessView(
                access: calendar.access, symbol: "calendar", what: "calendars", settingsPane: "Privacy_Calendars",
                request: calendar.requestAccess)
        } else {
            GeometryReader { proxy in
                // Once a minute, for the countdown, the fold, and which day is today; never faster.
                TimelineView(.everyMinute) { context in
                    tab(now: context.date, size: proxy.size)
                }
            }
            // The next look, and Home's glance at the day, start from today.
            .onDisappear { calendar.select(.now) }
        }
    }

    /// The strip, the chosen day, and the field. Where there's room the tasks card stays beside the
    /// day, whichever day, empty or not; a short notch packs the strip into one line a day and lists
    /// the tasks under the events. They step aside while an event is edited, and so does the field,
    /// which gives the editor room in the smallest notch.
    private func tab(now: Date, size: CGSize) -> some View {
        let compact = size.height < 150
        let tasks = calendar.dueTasks
        let beside = !compact && size.width >= 400 && calendar.readsTasks && editing == nil
        return VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            strip(now: now, compact: compact)
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 10) {
                    agenda(now: now, compact: compact, tasks: beside ? [] : tasks)
                    if beside { tasksPane(tasks, now: now).frame(width: size.width * 0.36) }
                }
                .id(calendar.day)
                .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if editing == nil { field(compact: compact) }
        }
    }

    // MARK: The week

    /// How the strip sets its days apart, as the theme draws its controls: boxed where they're
    /// square, ruled like a desk calendar where they're outlined, and on their own otherwise.
    private enum Cells {
        case plain, ruled, boxed
    }

    private var cells: Cells {
        guard let controls = theme.controls else { return .plain }
        if controls.radius == 0 { return .boxed }
        return controls.style == .outline ? .ruled : .plain
    }

    /// The seven days between the arrows that change the week.
    private func strip(now: Date, compact: Bool) -> some View {
        let days = calendar.weekDays
        let today = Calendar.current.startOfDay(for: now)
        return HStack(spacing: 2) {
            weekArrow(ahead: false)
            ZStack {
                HStack(spacing: cells == .boxed ? 4 : 0) {
                    ForEach(days, id: \.self) { day in
                        dayCell(day, today: today, week: days.first, compact: compact)
                    }
                }
                .overlay(alignment: .trailing) { if cells == .ruled { rule } }
                .id(days.first)
                .transition(.push(from: forward ? .trailing : .leading))
            }
            .clipShape(Rectangle().inset(by: -3))  // a hard shadow shows; the week leaving doesn't
            weekArrow(ahead: true)
        }
        .frame(height: compact ? 28 : 46)
    }

    /// A day: its weekday, its date (today's in red), and a dot per event, up to four. The chosen
    /// one wears the theme's selection, which slides along to the next one chosen.
    private func dayCell(_ day: Date, today: Date, week: Date?, compact: Bool) -> some View {
        let chosen = day == calendar.day
        let events = calendar.events(on: day)
        let onAccent = chosen && theme.selectsOnAccent
        // Red as in Calendar: the theme has no color of its own for today.
        let number =
            onAccent
            ? theme.color(.onAccent)
            : day == today ? Color.red : day < today && !chosen ? theme.color(.secondary) : theme.color(.ink)
        let count = events.isEmpty ? "no events" : events.count == 1 ? "1 event" : "\(events.count) events"
        let name = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let weekday = Text(day, format: .dateTime.weekday(compact ? .narrow : .abbreviated))
            .textCase(.uppercase)
            .themeFont(.body, size: compact ? 8.5 : 9.5, weight: .semibold)
            .tracking(0.6)
            .themeSelectionInk(chosen, unlit: 0.6)
        let date = Text(day, format: .dateTime.day())
            .themeFont(.display, size: compact ? 13 : 17, weight: .semibold)
            .monospacedDigit()
            .foregroundStyle(number)
        return Button {
            go(to: day)
        } label: {
            VStack(spacing: compact ? 2 : 3) {
                if compact {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        weekday.fixedSize()
                        date.fixedSize()
                    }
                } else {
                    weekday
                    date
                }
                HStack(spacing: 3) {
                    ForEach(events.prefix(4)) { event in
                        CalendarDot(
                            color: onAccent ? theme.color(.onAccent) : event.color?.color ?? theme.color(.ink),
                            size: compact ? 4 : 5)
                    }
                }
                .frame(height: compact ? 4 : 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if chosen {
                    SelectionMark(in: RoundedRectangle(cornerRadius: 11, style: .continuous), strength: 0.14)
                        .matchedGeometryEffect(id: week, in: selection)
                }
            }
            .background {
                if cells == .boxed { Color.clear.themePlatter(0.04, in: Rectangle()) }
            }
            .overlay(alignment: .leading) { if cells == .ruled { rule } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)\(day == today ? ", today" : ""), \(count)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// A hairline between the days of a ruled strip.
    private var rule: some View {
        Rectangle()
            .fill(theme.controls?.lineColor?.color ?? theme.color(.ink).opacity(0.2))
            .frame(width: 1)
    }

    private func weekArrow(ahead: Bool) -> some View {
        Button {
            go(by: ahead ? 7 : -7)
        } label: {
            ThemeSymbol(ahead ? "chevron.right" : "chevron.left")
                .themeFont(.body, size: 11, weight: .semibold)
                .foregroundStyle(.themeSecondary)
                .frame(width: 18)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(ahead ? "Next week" : "Previous week")
        .accessibilityLabel(ahead ? "Next week" : "Previous week")
    }

    private func go(by days: Int) {
        go(to: Calendar.current.date(byAdding: .day, value: days, to: calendar.day) ?? calendar.day)
    }

    /// Chooses the day `date` falls on: the selection slides to it within the week, and another week
    /// pushes in from its side.
    private func go(to date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        guard day != calendar.day else { return }
        editing = nil
        showsEarlier = false
        if calendar.weekDays.contains(day) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { calendar.select(day) }
        } else {
            forward = day > calendar.day
            // Once the strip has taken the new side, so the old week leaves by it too.
            let calendar = calendar
            let push: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.3)
            Task { @MainActor in
                withAnimation(push) { calendar.select(day) }
            }
        }
    }

    // MARK: The day

    /// The day's events under its name. On today the finished ones fold into "N earlier" and the
    /// next one is lit. `tasks` follow the events, when they aren't beside them. A short notch
    /// leaves the name to the strip and puts the fold after the events, so the next one comes first.
    private func agenda(now: Date, compact: Bool, tasks: [TaskItem]) -> some View {
        let isToday = calendar.day == Calendar.current.startOfDay(for: now)
        let events = calendar.events
        let earlier = isToday ? events.filter { !$0.isAllDay && $0.end <= now } : []
        let shown = showsEarlier ? events : events.filter { event in !earlier.contains { $0.id == event.id } }
        let next = isToday ? shown.first { !$0.isAllDay && $0.end > now && !$0.isDeclined } : nil
        return VStack(alignment: .leading, spacing: 0) {
            if !compact {
                header(isToday: isToday, count: events.count, earlier: earlier.count)
            }
            ScrollViewReader { list in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(shown) { event in
                            eventRow(event, now: now, isNext: event.id == next?.id, compact: compact)
                        }
                        if shown.isEmpty { emptyLine(isToday: isToday, any: !events.isEmpty) }
                        if compact, !earlier.isEmpty {
                            earlierButton(earlier.count).frame(height: 20).padding(.leading, 8)
                        }
                        if !tasks.isEmpty {
                            tasksTitle(tasks.count).padding(.leading, 8).padding(.top, 2)
                            ForEach(tasks) { task in taskRow(task, now: now).padding(.leading, 8) }
                        }
                    }
                    .padding(.vertical, compact ? 1 : 3)
                }
                .fadingEdges(length: compact ? 3 : 5)
                // In a small notch the editor can open below the fold.
                .onChange(of: editing) { _, id in
                    guard let id else { return }
                    withAnimation(spring) { list.scrollTo(id) }
                }
            }
        }
    }

    /// The day's name (a click opens Calendar), its date and what's on it, then the way back to
    /// today from another day, or today's fold.
    private func header(isToday: Bool, count: Int, earlier: Int) -> some View {
        let summary =
            isToday && count > 0
            ? "\(count - earlier) left" : count == 0 ? "no events" : count == 1 ? "1 event" : "\(count) events"
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            Button(action: calendar.openCalendarApp) {
                Text(calendar.day, format: .dateTime.weekday(.wide))
                    .themeFont(.display, size: 14, weight: .semibold)
            }
            .buttonStyle(.plain)
            .help("Open Calendar")
            Text("\(calendar.day.formatted(.dateTime.month(.abbreviated).day())) · \(summary)")
                .themeFont(.body, size: 11)
                .foregroundStyle(.themeSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !isToday {
                Button("Today") { go(to: .now) }
                    .buttonStyle(.plain)
                    .themeFont(.body, size: 11, weight: .semibold)
                    .foregroundStyle(.themeSecondary)
                    .help("Back to today")
            }
            if earlier > 0 { earlierButton(earlier) }
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .frame(height: 20)
    }

    private func earlierButton(_ count: Int) -> some View {
        Button {
            withAnimation(spring) { showsEarlier.toggle() }
        } label: {
            HStack(spacing: 3) {
                Text("\(count) earlier")
                ThemeSymbol("chevron.right")
                    .imageScale(.small)
                    .rotationEffect(.degrees(showsEarlier ? -90 : 90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .themeFont(.body, size: 11, weight: .medium)
        .foregroundStyle(.themeSecondary)
        .help(showsEarlier ? "Fold the finished events away" : "Show the finished events")
    }

    private func emptyLine(isToday: Bool, any: Bool) -> some View {
        Text(isToday ? (any ? "Nothing else today" : "Nothing today. Enjoy the free time.") : "Nothing planned")
            .themeFont(.body, size: 12)
            .foregroundStyle(.themeSecondary)
            .padding(.leading, 8)
            .frame(height: 24)
    }

    @ViewBuilder private func eventRow(_ event: DayEvent, now: Date, isNext: Bool, compact: Bool) -> some View {
        if editing == event.id {
            EventEditor(event: event) { title, start, end in
                if calendar.update(event, title: title, start: start, end: end) {
                    withAnimation(spring) { editing = nil }
                }
            } cancel: {
                withAnimation(spring) { editing = nil }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        } else {
            EventRow(calendar: calendar, event: event, now: now, isNext: isNext, height: compact ? 21 : 23) {
                withAnimation(spring) { editing = event.id }
            }
            .transition(.opacity)
        }
    }

    // MARK: Tasks

    /// The day's tasks and the overdue ones beside its events, on a card of their own that stays on
    /// every day, saying so when there are none.
    private func tasksPane(_ tasks: [TaskItem], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tasksTitle(tasks.count)
            if tasks.isEmpty {
                Text("Nothing due")
                    .themeFont(.body, size: 11)
                    .foregroundStyle(.themeTertiary)
                    .frame(height: 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tasks) { task in taskRow(task, now: now) }
                    }
                    .padding(.bottom, 4)
                }
                .fadingEdges(length: 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themePlatter(0.06, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tasksTitle(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Tasks").themeFont(.display, size: 13, weight: .semibold)
            if count > 0 { Text("\(count) left").themeFont(.body, size: 11).foregroundStyle(.themeSecondary) }
        }
        .frame(height: 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// A task: its box completes it, and the rest of the row opens it, in Tasks or else Reminders.
    private func taskRow(_ task: TaskItem, now: Date) -> some View {
        HStack(spacing: 7) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                    calendar.complete(task)
                }
            } label: {
                TaskBox(color: task.color?.color).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")
            Button {
                calendar.open(task)
            } label: {
                HStack(spacing: 7) {
                    Text(task.title).themeFont(.body, size: 12).lineLimit(1)
                    Spacer(minLength: 0)
                    if let due = dueText(task, now: now) {
                        Text(due)
                            .themeFont(.body, size: 10.5)
                            .monospacedDigit()
                            .foregroundStyle(task.isOverdue(now: now) ? Color.red : theme.color(.secondary))
                            .layoutPriority(1)  // when outranks the title, which truncates first
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open this task")
            .accessibilityLabel("Open \(task.title)")
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background {
            Color.clear.themePlatter(
                hoveredTask == task.id ? 0.07 : 0, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, -4)  // the light reaches past the row; the row lines up with the title
        .onHover { inside in
            if inside {
                hoveredTask = task.id
            } else if hoveredTask == task.id {
                hoveredTask = nil
            }
        }
        .transition(.opacity)
    }

    /// A task's time on its day; for one due on another day (an overdue one), that day.
    private func dueText(_ task: TaskItem, now: Date) -> String? {
        guard let due = task.due else { return nil }
        if Calendar.current.startOfDay(for: due) != calendar.day {
            return DueLabel.text(for: due, hasTime: false, now: now)
        }
        return task.hasTime ? clock(due) : nil
    }

    // MARK: Adding

    /// Adds an event from plain words. In an empty field the arrows choose the day, with Shift the week.
    private func field(compact: Bool) -> some View {
        let placeholder = "Add in plain words: \u{201C}Lunch tomorrow 1pm for 1h\u{201D}"
        return HStack(spacing: 7) {
            ThemeSymbol("plus")
                .themeFont(.body, size: 11, weight: .semibold)
                .foregroundStyle(.themeSecondary)
            TextField(placeholder, text: $draft, prompt: theme.prompt(placeholder, .callout))
                .textFieldStyle(.plain)
                .themeFont(.body, .callout)
                .onSubmit {
                    // Text without a time stays in the field so it can be finished.
                    if calendar.addEvent(draft) { draft = "" }
                }
                .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                    guard draft.isEmpty else { return .ignored }
                    let step = press.modifiers.contains(.shift) ? 7 : 1
                    go(by: press.key == .leftArrow ? -step : step)
                    return .handled
                }
            if let notice = calendar.notice {
                Text(notice)
                    .themeFont(.body, size: 11, weight: .medium)
                    .foregroundStyle(.themeSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: compact ? 22 : 28)
        .themePlatter(0.08, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: calendar.notice)
    }
}

/// A time of day without its AM or PM, as a narrow column shows it: "9:30", "11:00", or "21:30".
private func clock(_ date: Date) -> String {
    let text = date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
    // Some 12-hour locales pad the hour once AM or PM is gone ("08:47"); 24-hour ones mean it.
    return usesTwelveHours && text.hasPrefix("0") ? String(text.dropFirst()) : text
}

// ponytail: read once per launch; a clock switched to 24 hours meanwhile shows after a relaunch.
private let usesTwelveHours =
    DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false

/// "in 8 min", "in 1 h 20 min", or "now" once it has started; rounded up, as a countdown is.
private func countdown(to start: Date, now: Date) -> String {
    let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
    guard minutes > 0 else { return "now" }
    let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
    return hours == 0 ? "in \(minutes) min" : rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
}

/// A calendar's color as a dot: round, or square in a theme whose controls are square.
private struct CalendarDot: View {
    let color: Color
    let size: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if theme.controls?.radius == 0 { Rectangle().fill(color) } else { Circle().fill(color) }
        }
        .frame(width: size, height: size)
    }
}

/// A task's checkbox in its list's color: round, or square in a theme whose controls have corners
/// of their own.
private struct TaskBox: View {
    let color: Color?
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = theme.controls?.radius == nil ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 2.5))
        shape.stroke(color ?? theme.color(.ink).opacity(0.5), lineWidth: 1.3).frame(width: 12, height: 12)
    }
}

/// One event on one line: when, its calendar's color, its title, and where it is or its call. The
/// next one today is lit, with its countdown and Join (⌘J). Hovering one of your own events shows
/// Edit and Delete; Delete asks for a second click before it deletes. Double-clicking or the context
/// menu edits it too.
private struct EventRow: View {
    let calendar: CalendarFeature
    let event: DayEvent
    let now: Date
    let isNext: Bool
    let height: CGFloat
    let edit: () -> Void

    @State private var hovering = false
    /// Delete was clicked once: the next click deletes.
    @State private var confirming = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    /// Lit on the accent, as this theme marks a chosen tab.
    private var onAccent: Bool { isNext && theme.selectsOnAccent }
    private var dim: ThemeStyle { onAccent ? .themeOnAccent : .themeSecondary }

    var body: some View {
        let past = !event.isAllDay && event.end <= now
        let joinable = event.meeting != nil && !past && !event.isDeclined
        HStack(spacing: 6) {
            when
                .themeFont(.display, size: 11, weight: isNext ? .bold : .regular)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isNext ? (onAccent ? ThemeStyle.themeOnAccent : .themeInk) : dim)
                .frame(width: 34, alignment: .trailing)
            CalendarDot(color: onAccent ? theme.color(.onAccent) : event.color?.color ?? theme.color(.ink), size: 7)
            Text(event.title)
                .themeFont(.display, size: 12.5, weight: .semibold)
                .lineLimit(1)
            Spacer(minLength: 2)
            if hovering, event.isEditable {
                actions.fixedSize().transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            } else if isNext {
                Text(countdown(to: event.start, now: now))
                    .themeFont(.body, size: 10.5, weight: .bold)
                    .monospacedDigit()
                    .foregroundStyle(
                        onAccent ? theme.color(.onAccent) : theme.appearance == .dark ? Color.orange : Color.red
                    )
                    .fixedSize()
            } else if !(hovering && joinable) {
                meta
            }
            if joinable, isNext || hovering, let meeting = event.meeting {
                joinButton(meeting)
            }
        }
        .themeSelectionInk(onAccent, unlit: 1)
        .padding(.leading, 2)
        .padding(.trailing, isNext ? 3 : 6)
        .frame(height: height)
        .opacity(past && !hovering ? 0.45 : 1)
        .background { backing }
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                hovering = inside
                if !inside { confirming = false }
            }
        }
        .onTapGesture(count: 2) { if event.isEditable { edit() } }
        .contextMenu {
            if event.isEditable { Button("Edit", action: edit) }
            if let meeting = event.meeting {
                Button("Join \(meeting.service)") { calendar.join(event) }.disabled(!joinable)
                Button("Copy Link") { calendar.copyLink(event) }
            }
            if event.isEditable {
                Divider()
                Button("Delete Event", role: .destructive) { calendar.delete(event) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if joinable { Button("Join") { calendar.join(event) } }
            if event.isEditable {
                Button("Edit", action: edit)
                Button("Delete") { calendar.delete(event) }
            }
        }
    }

    /// When it starts; for one that began on an earlier day, when it ends, or all day.
    private var when: Text {
        let day = calendar.day
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        if event.isAllDay || event.start < day && event.end >= next { return Text("All day") }
        if event.start < day { return Text("\u{2013}\(clock(event.end))") }
        return Text(clock(event.start))
    }

    /// Its call's service, or where it is.
    private var meta: some View {
        Group {
            if let meeting = event.meeting {
                HStack(spacing: 4) {
                    ThemeSymbol("video.fill").imageScale(.small)
                    Text(meeting.service)
                }
            } else if let place = event.place {
                Text(place)
            }
        }
        .themeFont(.body, size: 10.5)
        .foregroundStyle(dim)
        .lineLimit(1)
        .frame(maxWidth: 76, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The next event lies on the theme's selection: the accent where a chosen tab does, its
    /// calendar's color where the theme draws no controls of its own, else a raised card.
    @ViewBuilder private var backing: some View {
        if isNext {
            if theme.selectsOnAccent {
                SelectionMark(in: shape)
            } else if theme.controls == nil {
                let tint = event.color?.color ?? theme.color(.accent)
                shape.fill(tint.opacity(0.16)).overlay(shape.strokeBorder(tint.opacity(0.4), lineWidth: 1))
            } else {
                Color.clear.themePlatter(0.1, in: shape)
            }
        } else {
            Color.clear.themePlatter(hovering ? 0.07 : 0, in: shape)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: edit) {
                ThemeSymbol("pencil").contentShape(Rectangle())
            }
            .help("Edit")
            .accessibilityLabel("Edit")
            Button {
                if confirming {
                    calendar.delete(event)
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                        confirming = true
                    }
                }
            } label: {
                if confirming {
                    Text("Delete")
                        .themeFont(.body, size: 10.5, weight: .semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
                } else {
                    ThemeSymbol("trash").contentShape(Rectangle())
                }
            }
            .help(confirming ? "Click again to delete" : "Delete")
            .accessibilityLabel("Delete")
        }
        .buttonStyle(.plain)
        .themeFont(.body, size: 11)
        .foregroundStyle(onAccent ? ThemeStyle.themeOnAccent : .themeInk.opacity(0.8))
    }

    /// On the next event, in the theme's strongest button (⌘J joins it); on a hovered one, quieter.
    private func joinButton(_ meeting: MeetingLink) -> some View {
        let fill: (back: Color, ink: Color)? =
            !isNext
            ? nil
            : theme.selectsOnAccent
                ? (theme.color(.onAccent), theme.color(.accent))
                : theme.controls == nil
                    ? (theme.color(.ink), theme.surface.color.color) : (theme.color(.accent), theme.color(.onAccent))
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius ?? 9, style: .continuous)
        return Button {
            calendar.join(event)
        } label: {
            ThemeLabel("Join", symbol: "video.fill")
                .themeFont(.body, size: 10.5, weight: .semibold)
                .imageScale(.small)
                .foregroundStyle(fill?.ink ?? theme.color(.ink))
                .fixedSize()
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background {
                    if let fill { shape.fill(fill.back) } else { Color.clear.themePlatter(0.14, in: shape) }
                }
                .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle())
        .keyboardShortcut(isNext ? KeyboardShortcut("j", modifiers: .command) : nil)
        .help("Join on \(meeting.service)\(isNext ? " (\u{2318}J)" : ""). Right-click to copy the link.")
    }
}

/// An event being changed in place: its title, and when it starts and ends (an all-day event keeps
/// its days). Moving the start keeps the length. Return or Save saves; Cancel leaves it as it was.
private struct EventEditor: View {
    let event: DayEvent
    let save: (_ title: String, _ start: Date, _ end: Date) -> Void
    let cancel: () -> Void

    @Environment(\.theme) private var theme

    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @FocusState private var focused: Bool

    init(
        event: DayEvent, save: @escaping (_ title: String, _ start: Date, _ end: Date) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.event = event
        self.save = save
        self.cancel = cancel
        _title = State(initialValue: event.title)
        _start = State(initialValue: event.start)
        _end = State(initialValue: event.end)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (event.isAllDay || end > start)
    }

    /// Two lines, so it fits even the smallest notch (with the new-event field out of the way): the
    /// title with Cancel and Save, then the times.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CalendarDot(color: event.color?.color ?? theme.color(.ink), size: 7)
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .themeFont(.display, size: 12.5, weight: .semibold)
                    .focused($focused)
                    .takesKeyboard(true)
                    .onSubmit { if canSave { save(title, start, end) } }
                buttons
            }
            HStack(spacing: 6) { when }
                .padding(.leading, 15)  // under the title, past the dot
                .datePickerStyle(.field)
                .labelsHidden()
        }
        .themeFont(.body, .caption, weight: .semibold)
        .buttonStyle(.plain)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .themePlatter(0.08, in: RoundedRectangle(cornerRadius: 9))
        .onChange(of: start) { old, new in end += new.timeIntervalSince(old) }
        .onAppear { Task { @MainActor in focused = true } }
    }

    @ViewBuilder private var when: some View {
        if event.isAllDay {
            Text("All day").themeFont(.body, .caption).foregroundStyle(.themeSecondary)
        } else {
            DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
            Text("\u{2013}").foregroundStyle(.themeSecondary)
            DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
        }
    }

    @ViewBuilder private var buttons: some View {
        Button("Cancel", action: cancel)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .themePlatter(0.1, in: Capsule())
        Button("Save") { save(title, start, end) }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .themePlatter(canSave ? 0.25 : 0.08, in: Capsule())
            .disabled(!canSave)
    }
}

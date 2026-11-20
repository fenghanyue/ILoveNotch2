// SPDX-License-Identifier: MIT
import AppKit
import EventKit
import NotchCore
import Observation
import SwiftUI

/// One event on the agenda, copied out of EventKit so it can cross threads.
public struct DayEvent: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var color: RGB?
    /// Where it happens: the first line of its location, unless that's a link.
    public var place: String?
    /// The video call to join, when the event has a link to one.
    public var meeting: MeetingLink?
    /// Declined, or canceled by the organizer: nothing to join.
    public var isDeclined: Bool
    /// Yours to change from the notch: in a calendar that takes changes, with nobody else invited.
    /// Invitations and meetings are changed in Calendar, which can tell the others.
    public var isEditable: Bool

    init(_ event: EKEvent) {
        id = Self.id(for: event)
        title = event.title ?? "Untitled"
        start = event.startDate
        end = event.endDate
        isAllDay = event.isAllDay
        color = RGB(event.calendar?.cgColor)
        let line = event.location?.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespaces)
        place = line.flatMap { $0.isEmpty || $0.contains("://") ? nil : $0 }
        meeting = MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
        isDeclined =
            event.status == .canceled
            || event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
        isEditable = event.calendar?.allowsContentModifications == true && (event.attendees ?? []).isEmpty
    }

    init(
        id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, color: RGB? = nil,
        place: String? = nil, meeting: MeetingLink? = nil, isDeclined: Bool = false, isEditable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.color = color
        self.place = place
        self.meeting = meeting
        self.isDeclined = isDeclined
        self.isEditable = isEditable
    }

    /// Recurring events share an identifier, so the start date keeps occurrences apart.
    static func id(for event: EKEvent) -> String {
        "\(event.calendarItemIdentifier)@\(event.startDate.timeIntervalSince1970)"
    }

    /// All-day events first, then by start time.
    static func agendaOrder(_ lhs: DayEvent, _ rhs: DayEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        return (lhs.start, lhs.title) < (rhs.start, rhs.title)
    }
}

/// The week of the chosen day from the user's calendars, with that day's events and its tasks, and
/// a field to add an event. It asks for access only when the user taps the button, and reads the
/// week (one bounded week-long query, plus one for the reminders due by its end when Reminders
/// access is already allowed) only while the tab is on screen, again when another week is chosen,
/// refreshing on EventKit's change notification rather than polling. With access, it also counts
/// down to the next meeting with a video link while the tab is off screen: one bounded query for it
/// and one deadline, looked at again when the calendars change.
@MainActor
@Observable
public final class CalendarFeature: NotchFeature {
    public let id = FeatureID.calendar
    public var phase: FeaturePhase = .stopped {
        didSet {
            guard phase != oldValue else { return }
            update()
        }
    }
    public private(set) var access = EventAccess(.event)
    /// The day the agenda shows, at its start: today until another is chosen, and again once the tab
    /// is off screen.
    public private(set) var day = Calendar.current.startOfDay(for: .now)
    /// The chosen week's events by day, while the tab is on screen.
    private var weekEvents: [Date: [DayEvent]] = [:]
    /// Open reminders due in the chosen week, and the overdue ones whichever week it is, when
    /// Reminders access is allowed.
    private var weekTasks: [TaskItem] = []
    /// Whether the week's tasks are read: the setting is on and Reminders access was given. The
    /// tasks card shows whenever they are, empty or not.
    public private(set) var readsTasks = false
    /// The seven days of the chosen week, from the calendar's first weekday.
    public var weekDays: [Date] { Self.week(of: day) }
    /// The chosen day's events, all-day ones first.
    public var events: [DayEvent] { events(on: day) }
    /// The chosen day's tasks: due that day, and every overdue one, whichever day it is.
    public var dueTasks: [TaskItem] {
        Self.tasks(weekTasks, on: day, today: Calendar.current.startOfDay(for: .now))
    }
    /// A short confirmation or problem after adding an event. Clears itself.
    public private(set) var notice: String?
    /// Per-feature setting: include all-day events.
    public var showsAllDay: Bool {
        didSet {
            defaults.set(showsAllDay, forKey: Self.allDayKey)
            reload()
        }
    }
    /// Per-feature setting: list the tasks due today under the events.
    public var showsTasks: Bool {
        didSet {
            defaults.set(showsTasks, forKey: Self.showsTasksKey)
            reload()
        }
    }
    /// Per-feature setting: count down in the closed notch to the next meeting with a video link.
    public var countsDownToMeetings: Bool {
        didSet {
            defaults.set(countsDownToMeetings, forKey: Self.countdownKey)
            update()
        }
    }
    /// Raised when a meeting's countdown starts, with the meeting's name.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?
    /// The countdown to the next meeting, or nil when there's none to show.
    @ObservationIgnored public var onOngoing: ((Activity?) -> Void)?
    /// Shows a task clicked beside the day's events where it lives, by its ID. Without it, a click
    /// opens Reminders.
    @ObservationIgnored public var onOpenTask: ((TaskItem.ID) -> Void)?

    // ponytail: overdue reminders can pile up, so the agenda shows a bounded number.
    nonisolated static let dueTaskLimit = 20
    // ponytail: a fixed five minutes' warning; a picker in Calendar's settings if people want more.
    static let lead: TimeInterval = 5 * 60
    /// How far ahead the next meeting is looked for; the countdown looks again when this runs out.
    static let horizon: TimeInterval = 24 * 3600
    private static let allDayKey = "calendar.showsAllDay"
    private static let showsTasksKey = "calendar.showsTasks"
    private static let countdownKey = "calendar.countsDownToMeetings"
    @ObservationIgnored private let eventStore: EventStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var changes: NSObjectProtocol?
    @ObservationIgnored private var clearNotice: Task<Void, Never>?
    @ObservationIgnored private var wake: Task<Void, Never>?
    /// The meeting the notch is counting down to.
    private(set) var countingDown: DayEvent?
    /// Meetings the user joined from the notch, which don't count down again.
    @ObservationIgnored private var joined: Set<DayEvent.ID> = []

    public init(eventStore: EventStore, defaults: UserDefaults = .standard) {
        self.eventStore = eventStore
        self.defaults = defaults
        showsAllDay = defaults.object(forKey: Self.allDayKey) as? Bool ?? true
        showsTasks = defaults.object(forKey: Self.showsTasksKey) as? Bool ?? true
        countsDownToMeetings = defaults.object(forKey: Self.countdownKey) as? Bool ?? true
    }

    public var view: some View { CalendarView(calendar: self) }

    /// Whether the feature is listening for calendar changes.
    var isObserving: Bool { changes != nil }

    public func requestAccess() {
        eventStore.store.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor in self?.update() }
        }
    }

    /// Re-reads access, which may have changed in System Settings.
    public func refreshAccess() { access = EventAccess(.event) }

    /// The events on `day` (a day's start) in the chosen week.
    public func events(on day: Date) -> [DayEvent] { weekEvents[day] ?? [] }

    /// Shows the agenda of the day `date` falls on, reading its week when that's another one.
    public func select(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        guard day != self.day else { return }
        let sameWeek = weekDays.contains(day)
        self.day = day
        if !sameWeek { reload() }
    }

    /// Adds an event typed as "Lunch with Sam tomorrow 1pm for 90 min" to the default calendar; a
    /// time with no day ("Lunch 1pm") is on the chosen day. Returns whether it was added; text
    /// without a date or time is left for the user to finish.
    @discardableResult
    public func addEvent(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, access == .granted else { return false }
        guard let draft = Self.draft(text, on: day) else {
            show(notice: "Add when it happens, like \u{201C}tomorrow 1pm\u{201D}")
            return false
        }
        let store = eventStore.store
        guard let calendar = store.defaultCalendarForNewEvents else {
            show(notice: "No calendar to add the event to")
            return false
        }
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.calendar = calendar
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = draft.start.addingTimeInterval(draft.duration)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            Log.features.error("Couldn't add an event: \(error.localizedDescription, privacy: .public)")
            show(notice: "Couldn't add the event")
            return false
        }
        let when = DueLabel.text(for: draft.start, hasTime: !draft.isAllDay)
        show(notice: "Added \u{201C}\(draft.title)\u{201D}, \(when)")
        reload()
        return true
    }

    /// Renames or moves an event of yours: only this occurrence, for a repeating one. An all-day
    /// event keeps its days. Returns whether it was saved.
    @discardableResult
    public func update(_ event: DayEvent, title: String, start: Date, end: Date) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, event.isAllDay || end > start, let stored = stored(event) else { return false }
        stored.title = title
        if !event.isAllDay {
            stored.startDate = start
            stored.endDate = end
        }
        do {
            try eventStore.store.save(stored, span: .thisEvent, commit: true)
        } catch {
            Log.features.error("Couldn't change an event: \(error.localizedDescription, privacy: .public)")
            show(notice: "Couldn't change the event")
            return false
        }
        reload()
        watchMeetings()
        return true
    }

    /// Deletes an event of yours from its calendar: only this occurrence, for a repeating one.
    public func delete(_ event: DayEvent) {
        guard let stored = stored(event) else { return }
        do {
            try eventStore.store.remove(stored, span: .thisEvent, commit: true)
        } catch {
            Log.features.error("Couldn't delete an event: \(error.localizedDescription, privacy: .public)")
            show(notice: "Couldn't delete the event")
            return
        }
        weekEvents = weekEvents.mapValues { $0.filter { $0.id != event.id } }
        show(notice: "Deleted \u{201C}\(event.title)\u{201D}")
        watchMeetings()
    }

    /// The EventKit event behind `event`: that occurrence, for a repeating one, whose identifier is
    /// shared by every occurrence.
    private func stored(_ event: DayEvent) -> EKEvent? {
        guard access == .granted, event.isEditable else { return nil }
        let store = eventStore.store
        let around = store.predicateForEvents(withStart: event.start - 1, end: event.end + 1, calendars: nil)
        return store.events(matching: around).first { DayEvent.id(for: $0) == event.id }
    }

    /// Ticks off a task listed beside the day's events.
    public func complete(_ task: TaskItem) {
        let store = eventStore.store
        guard let reminder = store.calendarItem(withIdentifier: task.id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            weekTasks.removeAll { $0.id == task.id }
        } catch {
            Log.features.error("Couldn't complete a reminder: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Shows a task where it lives: on the Tasks tab, or in Reminders.
    public func open(_ task: TaskItem) {
        guard let onOpenTask else { return openRemindersApp() }
        onOpenTask(task.id)
    }

    /// Shows the given events and tasks in the chosen week as if access were granted. For tests and
    /// snapshots only.
    func show(events: [DayEvent], dueTasks: [TaskItem] = []) {
        access = .granted
        weekEvents = Self.group(events, into: weekDays)
        weekTasks = dueTasks
        readsTasks = showsTasks
    }

    private func show(notice text: String) {
        notice = text
        clearNotice?.cancel()
        clearNotice = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.notice = nil
        }
    }

    public func openCalendarApp() { Self.openApp("com.apple.iCal") }

    /// Opens Reminders. It can't be opened at one reminder: there's no public way to link to one.
    public func openRemindersApp() { Self.openApp("com.apple.reminders") }

    private static func openApp(_ bundleID: String) {
        let workspace = NSWorkspace.shared
        guard let app = workspace.urlForApplication(withBundleIdentifier: bundleID) else { return }
        workspace.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Opens the meeting's link, which hands it to the service's app, and ends its countdown.
    public func join(_ event: DayEvent) {
        guard let meeting = event.meeting else { return }
        NSWorkspace.shared.open(meeting.url)
        joined.insert(event.id)
        watchMeetings()
    }

    public func copyLink(_ event: DayEvent) {
        guard let meeting = event.meeting else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(meeting.url.absoluteString, forType: .string)
    }

    /// Listens for calendar changes while the agenda is on screen or a countdown may be needed, and
    /// holds the week's events only while they're on screen; off screen, the agenda goes back to today.
    private func update() {
        refreshAccess()
        let listens = access == .granted && (phase == .foreground || phase == .background && countsDownToMeetings)
        if listens, changes == nil {
            changes = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: eventStore.store, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reload()
                    self?.watchMeetings()
                }
            }
        } else if !listens, let changes {
            NotificationCenter.default.removeObserver(changes)
            self.changes = nil
        }
        if phase == .foreground {
            reload()
        } else {
            weekEvents = [:]
            weekTasks = []
            day = Calendar.current.startOfDay(for: .now)
        }
        watchMeetings()
    }

    /// Reads the chosen week: its events in one query, and the reminders due by its end.
    private func reload() {
        guard access == .granted, phase == .foreground else { return }
        let calendar = Calendar.current
        let days = weekDays
        guard let start = days.first, let last = days.last,
            let end = calendar.date(byAdding: .day, value: 1, to: last)
        else { return }
        let store = eventStore.store
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).map(DayEvent.init).filter { showsAllDay || !$0.isAllDay }
        weekEvents = Self.group(events, into: days)
        // Tasks come along only when Reminders access was already given in the Tasks tab.
        readsTasks = showsTasks && EventAccess(.reminder) == .granted
        guard readsTasks else {
            weekTasks = []
            return
        }
        // Every day of every week shows the overdue ones, so one query reads all that's due by the
        // week's end, overdue or not, and keeps what the week shows.
        let today = calendar.startOfDay(for: .now)
        let due = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        // @Sendable: EventKit calls back on its own queue (see TasksFeature.reload).
        store.fetchReminders(matching: due) { @Sendable [weak self] reminders in
            let items = Self.weekTasks((reminders ?? []).map(TaskItem.init), from: start, today: today)
            Task { @MainActor in
                guard let self, self.phase == .foreground, self.weekDays.first == start else { return }
                self.weekTasks = items
            }
        }
    }

    // MARK: The week

    /// The seven days of the week `day` falls in, each at its start, from the calendar's first weekday.
    static func week(of day: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// `events` by the days they fall on, each day's in agenda order. An event over midnight, or an
    /// all-day one over several days, is on every day it covers; one that ends at midnight isn't on
    /// the next day.
    static func group(_ events: [DayEvent], into days: [Date], calendar: Calendar = .current) -> [Date: [DayEvent]] {
        var grouped: [Date: [DayEvent]] = [:]
        for day in days {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            grouped[day] = events.filter { $0.start < next && ($0.end > day || $0.start >= day) }
                .sorted(by: DayEvent.agendaOrder)
        }
        return grouped
    }

    /// The tasks due on `day`, and the overdue ones (due before `today`) whichever day it is.
    static func tasks(_ tasks: [TaskItem], on day: Date, today: Date, calendar: Calendar = .current) -> [TaskItem] {
        tasks.filter { task in
            guard let due = task.due.map(calendar.startOfDay) else { return false }
            return due == day || due < today
        }
    }

    /// What the week from `start` keeps of the open tasks due by its end, soonest due first: every
    /// one due in it, and the overdue ones (due before `today`) from before it, the latest
    /// `dueTaskLimit` of those. What's due between today and the week shows on none of its days.
    nonisolated static func weekTasks(
        _ tasks: [TaskItem], from start: Date, today: Date, calendar: Calendar = .current
    ) -> [TaskItem] {
        let dated = tasks.filter { $0.due != nil }.sorted(by: TaskItem.order)
        let day = { (task: TaskItem) in calendar.startOfDay(for: task.due ?? start) }
        let overdue = dated.filter { day($0) < start && day($0) < today }
        return Array(overdue.suffix(dueTaskLimit)) + dated.filter { day($0) >= start }
    }

    /// A time of day or a length in an event's text ("1pm", "at 9:30", "noon", "for 1h"): what's left
    /// names a day, if anything does.
    private static let timeOfDay =
        #"\b(at\s+)?\d{1,2}(:\d\d)?\s*(am|pm|a\.m\.|p\.m\.)|\b(at\s+)?\d{1,2}:\d\d\b|\bat\s+\d{1,2}\b"#
        + #"|\b(noon|midnight)\b|\bfor\s+\d+(\.\d+)?\s*[a-z]+"#

    /// The event `text` describes. With a time but no day ("Lunch 1pm"), it's on `day`.
    static func draft(_ text: String, on day: Date, calendar: Calendar = .current) -> EventDraft? {
        guard var draft = EventDraft.parse(text, calendar: calendar) else { return nil }
        let dayless = text.replacingOccurrences(
            of: timeOfDay, with: " ", options: [.regularExpression, .caseInsensitive])
        guard !draft.isAllDay, EventDraft.parse(dayless, calendar: calendar) == nil else { return draft }
        let time = calendar.dateComponents([.hour, .minute], from: draft.start)
        draft.start =
            calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? draft.start
        return draft
    }

    // MARK: Meeting countdown

    /// The next meeting worth counting down to: timed, with a link, not declined, not joined yet, and
    /// not started.
    static func nextMeeting(in events: [DayEvent], after now: Date, skipping joined: Set<DayEvent.ID>) -> DayEvent? {
        events
            .filter { !$0.isAllDay && $0.meeting != nil && !$0.isDeclined && !joined.contains($0.id) && $0.start > now }
            .min { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// When to look again: when `next`'s countdown starts, when it ends because the meeting starts,
    /// or, with no meeting coming, when the look-ahead runs out.
    static func nextWake(for next: DayEvent?, now: Date) -> Date {
        guard let next else { return now + horizon }
        return next.start - lead > now ? next.start - lead : next.start
    }

    /// Counts down to the next meeting from `lead` before it until it starts, then moves on to the
    /// one after. Nothing runs while the notch is stopped or the countdown is off.
    private func watchMeetings() {
        wake?.cancel()
        wake = nil
        guard phase != .stopped, countsDownToMeetings, access == .granted else { return count(down: nil) }
        let now = Date.now
        let store = eventStore.store
        let ahead = store.predicateForEvents(withStart: now, end: now + Self.horizon, calendars: nil)
        let next = Self.nextMeeting(in: store.events(matching: ahead).map(DayEvent.init), after: now, skipping: joined)
        count(down: next.flatMap { $0.start - Self.lead <= now ? $0 : nil })
        let delay = Self.nextWake(for: next, now: now).timeIntervalSince(now)
        wake = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(delay, 0)), tolerance: .seconds(1)) } catch { return }
            self?.watchMeetings()
        }
    }

    /// Starts or ends the notch's countdown. A new countdown opens with the meeting's name.
    private func count(down meeting: DayEvent?) {
        guard meeting != countingDown else { return }
        countingDown = meeting
        guard let meeting else {
            onOngoing?(nil)
            return
        }
        onActivity?(Activity(feature: .calendar, symbol: "video.fill", title: meeting.title, duration: .seconds(4)))
        onOngoing?(
            Activity(
                feature: .calendar, symbol: "video.fill", title: "\(meeting.title) starts in", duration: .zero,
                countdown: meeting.start))
    }
}

// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI

/// The tasks tab as a board: Today (overdue first, in red), Upcoming by day with No date last, and
/// Done, what was finished today under an "N of M" bar. Each task is a small card with its box,
/// title, due time, and list; the one due now grows in place with Done and Snooze. Drag a card to
/// another column or day (Upcoming keeps its time, Today moves it to today, Done finishes it, and out
/// of Done it opens again), or within its run to set your own order. A click on the box finishes a
/// task, a click on the card opens it in place to show all of it (another click, or another card,
/// folds it), a double-click renames it, and + adds to that column in plain words, where a typed
/// date wins. Keys: the arrows choose a card and open it, ⌘← and ⌘→ move it a column, Space ticks
/// it, Return renames it, and ⌘L shows your lists as the columns. Due times change once a minute
/// at most.
struct TasksView: View {
    let tasks: TasksFeature
    /// The card the keys act on.
    @State private var chosen: TaskItem.ID?
    /// The one card open in full, which its column scrolls to.
    @State private var expanded: TaskItem.ID?
    /// The last click on a card, so a second one on it soon after renames it.
    @State private var lastClick: (id: TaskItem.ID, at: Date)?
    @State private var renaming: TaskItem.ID?
    /// The column whose + field is open.
    @State private var adding: TaskColumn.Kind?
    @State private var draft = ""
    /// Tasks just ticked: they show a check for a beat before moving to Done.
    @State private var ticking: Set<TaskItem.ID> = []
    /// The card being dragged, and where it would land.
    @State private var dragging: TaskItem?
    @State private var over: Landing?
    @FocusState private var focused: Bool
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    private var look: TasksLook { TasksLook(theme) }
    /// How cards change places: a spring, or at once with Reduce Motion.
    private var moving: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85) }
    /// How a slot opens under a dragged card: the cards slide apart, or with Reduce Motion it fades.
    private var opening: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3) }
    /// Show each card's list where the columns mix lists.
    private var showsList: Bool { !tasks.groupsByList && tasks.listID == nil && tasks.lists.count != 1 }

    var body: some View {
        if tasks.access != .granted {
            EventAccessView(
                access: tasks.access, symbol: "checklist", what: "reminders", settingsPane: "Privacy_Reminders",
                request: tasks.requestAccess)
        } else {
            // What's due, overdue, or due now changes by the minute, never faster.
            TimelineView(.everyMinute) { context in
                board(now: context.date)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            // A chosen card takes the keyboard, for the arrows, Space, and Return.
            .takesKeyboard(chosen != nil)
            .onChange(of: chosen) { _, id in if id != nil { focused = true } }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                step(press.key, command: press.modifiers.contains(.command))
            }
            .onKeyPress(.space) { tickChosen() }
            .onKeyPress(.return) {
                guard renaming == nil, adding == nil, let id = chosen, tasks.tasks.contains(where: { $0.id == id })
                else { return .ignored }
                renaming = id
                return .handled
            }
            .onKeyPress(.escape) {
                guard chosen != nil, renaming == nil, adding == nil else { return .ignored }
                choose(nil)
                return .handled
            }
            .onKeyPress(keys: ["l"]) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                withAnimation(moving) { tasks.groupsByList.toggle() }
                return .handled
            }
            .onContinuousHover { _ in
                // A drag let go outside the board leaves nothing to land.
                if dragging != nil, NSEvent.pressedMouseButtons == 0 {
                    dragging = nil
                    over = nil
                }
            }
            .overlay(alignment: .bottom) { noticeView }
            .animation(.easeInOut(duration: 0.2), value: tasks.notice)
            // A task another tab asked to show, as the board comes on screen or while it's there.
            .onAppear(perform: takeReveal)
            .onChange(of: tasks.revealing) { takeReveal() }
        }
    }

    /// Chooses and opens the task another tab asked to show; its column scrolls to it once it has
    /// it, which may be after the board has loaded.
    private func takeReveal() {
        guard let id = tasks.takeRevealing() else { return }
        chosen = id
        expanded = id
    }

    // MARK: Board

    /// The open columns side by side, Done narrower on the right. Lists that don't fit scroll sideways.
    private func board(now: Date) -> some View {
        let columns = tasks.columns(now: now)
        let open = columns.filter { $0.kind != .done }
        let done = columns.first { $0.kind == .done } ?? TaskColumn(kind: .done, title: "Done", runs: [])
        let due = tasks.dueNow(now: now)
        let openedColumn = open.first { $0.tasks.contains { $0.id == expanded } }?.kind
        return GeometryReader { proxy in
            let gap: CGFloat = 8
            let doneWidth = ((proxy.size.width - gap * 2) * 0.27).rounded()
            let lane = proxy.size.width - doneWidth - gap
            let count = CGFloat(max(open.count, 1))
            let fitted = ((lane - gap * (count - 1)) / count).rounded(.down)
            let width = max(fitted, 116)
            HStack(alignment: .top, spacing: gap) {
                let row = HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(open.enumerated()), id: \.element.id) { index, column in
                        columnView(column, first: index == 0, width: width, now: now, due: due)
                            .frame(width: width)
                            .id(column.kind)
                    }
                }
                if width > fitted {
                    ScrollViewReader { reader in
                        ScrollView(.horizontal) { row }
                            .scrollIndicators(.never)
                            .fadingEdges(.horizontal, length: 8)
                            .frame(width: lane)
                            // The open card's column comes into view, as its column scrolls to it.
                            .onChange(of: openedColumn) { _, kind in
                                guard let kind else { return }
                                withAnimation(moving) { reader.scrollTo(kind) }
                            }
                    }
                } else {
                    row
                }
                doneColumn(done, now: now).frame(width: doneWidth)
            }
            .frame(height: proxy.size.height)
        }
    }

    /// A column of open tasks: its heading with + over its runs, which scroll.
    private func columnView(_ column: TaskColumn, first: Bool, width: CGFloat, now: Date, due: TaskItem.ID?)
        -> some View
    {
        let lit = over == .column(column.kind)
        let inset = look.columnInset
        let opened = column.tasks.contains { $0.id == expanded } ? expanded : nil
        return VStack(alignment: .leading, spacing: 6) {
            columnHead(column)
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        if adding == column.kind { addField(column, now: now) }
                        ForEach(shownRuns(column, now: now)) { run in
                            if column.kind == .upcoming { runHead(run, now: now) }
                            ForEach(run.tasks) { task in
                                card(task, in: run, width: width - inset.leading - inset.trailing, now: now, due: due)
                            }
                            if over == .run(run.spot), !reduceMotion {
                                slot(lit: true).frame(height: 30).transition(.opacity)
                            }
                        }
                        if column.tasks.isEmpty, adding != column.kind, dragging == nil { emptyNote(column) }
                        if lit, !reduceMotion { slot(lit: true).frame(height: 30).transition(.opacity) }
                    }
                    .padding(.vertical, 4)  // clear of the fade at rest
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .fadingEdges(length: 4)
                // The card that opens scrolls in whole, the least way; a revealed one, once it loads.
                .onChange(of: opened) { _, id in
                    guard let id else { return }
                    withAnimation(moving) { reader.scrollTo(id) }
                }
            }
        }
        .padding(inset)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { columnBackdrop(first: first, lit: lit) }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let task = dragging else { return false }
            return drop(items.first, in: spot(for: column.kind, task), before: nil)
        } isTargeted: {
            mark(.column(column.kind), $0)
        }
    }

    /// Upcoming's runs, and while a card is dragged, the coming week's empty days to drop it on.
    private func shownRuns(_ column: TaskColumn, now: Date) -> [TaskRun] {
        guard column.kind == .upcoming, dragging != nil else { return column.runs }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let week = (1...6).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }.map(TaskSpot.day)
        let empty = (week + [.day(nil)]).filter { spot in !column.runs.contains { $0.spot == spot } }
        func day(_ run: TaskRun) -> Date {
            if case .day(let day?) = run.spot { return day }
            return .distantFuture  // No date, last
        }
        return (column.runs + empty.map { TaskRun(spot: $0, tasks: []) }).sorted { day($0) < day($1) }
    }

    /// A column's name and how many it holds, with + to add to it; on index cards, over a ruled line.
    private func columnHead(_ column: TaskColumn) -> some View {
        HStack(spacing: 6) {
            if let color = column.color {
                Circle().fill(theme.listInk(color.color)).frame(width: 7, height: 7)
            }
            Group {
                switch look {
                case .glass: Text(column.title).themeFont(.body, size: 13, weight: .semibold)
                case .cards: Text(column.title).themeFont(.display, size: 16, weight: .semibold)
                case .console: Text(column.title.uppercased()).themeFont(.mono, size: 12, weight: .bold)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)  // "Upcoming" whole in the narrowest column
            .accessibilityAddTraits(.isHeader)
            countBadge(column.tasks.count)
            Spacer(minLength: 0)
            if column.kind != .done {
                Button {
                    withAnimation(moving) {
                        adding = column.kind
                        draft = ""
                    }
                } label: {
                    ThemeSymbol("plus")
                        .themeFont(.body, size: 12, weight: .semibold)
                        .frame(width: 18, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .foregroundStyle(.themeSecondary)
                .help("Add to \(column.title) in plain words")
                .accessibilityLabel("Add to \(column.title)")
            }
        }
        .frame(height: 20)
        .padding(.bottom, look == .cards ? 3 : 0)
        .overlay(alignment: .bottom) {
            if look == .cards { Rectangle().fill(.themeInk).frame(height: 1.5) }
        }
    }

    @ViewBuilder private func countBadge(_ count: Int) -> some View {
        switch look {
        case .glass:
            Text("\(count)")
                .themeFont(.body, size: 11, weight: .semibold)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .frame(height: 17)
                .themePlatter(0.12, in: Capsule())
        case .cards:
            Text("\(count)").themeFont(.display, size: 13).monospacedDigit().foregroundStyle(.themeSecondary)
        case .console:
            Text("[\(count)]").themeFont(.mono, size: 12).foregroundStyle(.themeSecondary)
        }
    }

    /// A day's heading in Upcoming. With a card over it, it lights, and says the time the card keeps.
    private func runHead(_ run: TaskRun, now: Date) -> some View {
        let lit = over == .run(run.spot)
        let title = taskDayTitle(run.spot, now: now)
        let console = look == .console
        return HStack(spacing: 6) {
            Text(console ? "# \(title.lowercased())" : title)
            if lit, case .day(_?) = run.spot, let task = dragging, task.hasTime, let due = task.due {
                let time = taskClock(due, twentyFour: console)
                Text(console ? "<- keeps \(time)" : "keeps \(time)")
                    .fontWeight(.medium)
                    .textCase(nil)
                    .tracking(0)
            }
        }
        .modifier(RunHeadFont(look: look))
        .foregroundStyle(lit ? (look == .cards ? ThemeStyle.themeAccent : .themeInk) : .themeSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            drop(items.first, in: run.spot, before: nil)
        } isTargeted: {
            mark(.run(run.spot), $0)
        }
        .accessibilityAddTraits(.isHeader)
    }

    /// A card in its run, a slot opening above it (below, dragged down its own run) while a card is
    /// over it. It drags, takes drops, and is chosen and opened by a click and renamed by a
    /// double-click.
    private func card(_ task: TaskItem, in run: TaskRun, width: CGFloat, now: Date, due: TaskItem.ID?) -> some View {
        let landing = over == .card(task.id) && dragging != nil && dragging?.id != task.id
        let below = landing && fromAbove(task, in: run)
        let editing = renaming == task.id
        return VStack(spacing: 6) {
            if landing, !below, !reduceMotion { slot(lit: true).frame(height: 30).transition(.opacity) }
            TaskCard(
                tasks: tasks, task: task, now: now, spot: run.spot, chosen: chosen == task.id, dueNow: due == task.id,
                expanded: expanded == task.id, ticked: ticking.contains(task.id), showsList: showsList,
                renaming: $renaming, tick: { tick(task) }
            )
            .overlay(alignment: below ? .bottom : .top) {
                // Reduce Motion: nothing slides; a line fades in where the card would land.
                if landing, reduceMotion {
                    Capsule().fill(.themeAccent).frame(height: 2).offset(y: below ? 4 : -4).transition(.opacity)
                }
            }
            if below, !reduceMotion { slot(lit: true).frame(height: 30).transition(.opacity) }
        }
        .opacity(dragging?.id == task.id ? 0.35 : 1)
        .contentShape(Rectangle())
        // One tap, telling a double-click by its timing: it gives way to the box and buttons inside,
        // which a tap alongside them would fire with, and a double-tap beside it would hold it back.
        .gesture(TapGesture().onEnded { click(task) }, including: editing ? .subviews : .all)
        .onDrag {
            dragging = task
            return NSItemProvider(object: task.title as NSString)
        } preview: {
            lifted(task, spot: run.spot, width: width, now: now)
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items.first, in: run.spot, before: task)
        } isTargeted: {
            mark(.card(task.id), $0)
        }
        .id(task.id)  // what its column scrolls to
        .transition(.opacity)
        .accessibilityAction(named: expanded == task.id ? "Hide Details" : "Show Details") { toggle(task.id) }
        .accessibilityAction(named: "Move Up") { step(task, by: -1, in: run) }
        .accessibilityAction(named: "Move Down") { step(task, by: 1, in: run) }
        .accessibilityAction(named: "Move to Today") { land(task, in: .today) }
        .accessibilityAction(named: "Move to Upcoming") { land(task, in: tasks.upcomingSpot(for: task)) }
    }

    /// The card as it's picked up: tilted 2° (flat with Reduce Motion) over a deeper shadow.
    private func lifted(_ task: TaskItem, spot: TaskSpot, width: CGFloat, now: Date) -> some View {
        let shape = RoundedRectangle(cornerRadius: look.cardRadius(theme), style: .continuous)
        let shadow = theme.appearance == .dark ? theme.surface.color.color : theme.color(.ink).opacity(0.25)
        return TaskCard(tasks: tasks, task: task, now: now, spot: spot, showsList: showsList, renaming: .constant(nil))
            .frame(width: width)
            .background(theme.surface.color.color, in: shape)
            .foregroundStyle(.themeInk)
            .environment(\.theme, theme)
            .environment(\.colorScheme, theme.appearance.colorScheme)
            .shadow(color: shadow.opacity(0.8), radius: 12, x: look == .cards ? 5 : 0, y: 8)
            .rotationEffect(.degrees(reduceMotion ? 0 : -2))
            .padding(18)  // room for the tilt and the shadow
    }

    @ViewBuilder private func emptyNote(_ column: TaskColumn) -> some View {
        let text =
            switch column.kind {
            case .today: "Nothing due"
            case .upcoming: "Nothing planned"
            default: "No tasks"
            }
        Text(look == .console ? "# \(text.lowercased())" : text)
            .themeFont(look.detailRole, size: 11)
            .foregroundStyle(.themeTertiary)
            .padding(.top, 2)
    }

    @ViewBuilder private func columnBackdrop(first: Bool, lit: Bool) -> some View {
        switch look {
        case .glass:
            Color.clear.themePlatter(
                lit ? 0.09 : 0.05, in: RoundedRectangle(cornerRadius: look.columnRadius(theme), style: .continuous))
        case .cards:
            ZStack(alignment: .leading) {
                if lit { Rectangle().fill(.themeAccent.opacity(0.06)) }
                // A hairline between columns, as on a ruled sheet.
                if !first { Rectangle().fill(.themeInk.opacity(0.28)).frame(width: 1).offset(x: -4.5) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .console:
            Rectangle().strokeBorder(lit ? theme.color(.ink) : theme.taskLine, lineWidth: 1)
        }
    }

    /// Where a dragged card would land: a dashed space a card wide.
    private func slot(lit: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: look.cardRadius(theme), style: .continuous)
        let ink = lit && look == .cards ? theme.color(.accent) : theme.color(.ink)
        let dashes = StrokeStyle(lineWidth: look == .console ? 1 : 1.5, dash: [4, 3])
        return shape.fill(ink.opacity(lit ? 0.06 : 0))
            .overlay(shape.strokeBorder(ink.opacity(lit ? 0.6 : 0.25), style: dashes))
    }

    // MARK: Done

    /// What was finished today, newest first, under its progress, with room to drop a card to finish.
    private func doneColumn(_ column: TaskColumn, now: Date) -> some View {
        let progress = tasks.progress(now: now)
        let lit = over == .column(.done)
        return VStack(alignment: .leading, spacing: 6) {
            columnHead(column)
            if progress.of > 0 { progressView(progress) }
            // The drop space fills what the list leaves; a long list scrolls, and the smallest notch
            // keeps only the list, which still takes drops.
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    doneRows(column.tasks)
                    dropZone(lit: lit).frame(minHeight: 30, maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 6) {
                    // Counts as short, so this fits whenever a row and the drop space do.
                    doneList(column.tasks).frame(minHeight: 0, idealHeight: 30, maxHeight: .infinity)
                    dropZone(lit: lit).frame(height: 24)
                }
                doneList(column.tasks)
            }
        }
        .padding(look.columnInset)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { columnBackdrop(first: false, lit: false) }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            drop(items.first, in: .done, before: nil)
        } isTargeted: {
            mark(.column(.done), $0)
        }
    }

    private func doneList(_ done: [TaskItem]) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) { doneRows(done) }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .fadingEdges(length: 6)
    }

    private func doneRows(_ done: [TaskItem]) -> some View {
        ForEach(done) { task in doneRow(task) }
    }

    /// A finished task, struck through, with when it was done; chosen, its whole title. Its box,
    /// Space, or a drag out opens it again.
    private func doneRow(_ task: TaskItem) -> some View {
        let lit = chosen == task.id
        let inverted = lit && theme.selectsOnAccent
        let color = look == .console || inverted ? theme.color(inverted ? .onAccent : .ink) : boxColor(task)
        return HStack(alignment: .top, spacing: 7) {
            Button {
                reopen(task)
            } label: {
                CheckBox(
                    done: true, color: color, square: look.squareBoxes(theme),
                    mark: inverted ? theme.color(.accent) : theme.surface.color.color
                )
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .accessibilityLabel("Reopen \(task.title)")
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title).strikethrough().themeFont(look.titleRole, size: 12)
                    .lineLimit(expanded == task.id ? nil : 1)
                if let at = task.completed, at != .distantPast {
                    Text(taskClock(at, twentyFour: look == .console)).themeFont(look.detailRole, size: 10.5)
                }
            }
            .foregroundStyle(inverted ? ThemeStyle.themeOnAccent : .themeSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background {
            if lit { SelectionMark(in: RoundedRectangle(cornerRadius: look.cardRadius(theme), style: .continuous)) }
        }
        .padding(.horizontal, -4)  // the mark reaches past the row; the row lines up with the cards
        .opacity(dragging?.id == task.id ? 0.35 : 1)
        .contentShape(Rectangle())
        .gesture(TapGesture().onEnded { toggle(task.id) })
        .onDrag {
            dragging = task
            return NSItemProvider(object: task.title as NSString)
        }
        .contextMenu {
            Button("Reopen") { reopen(task) }
            Divider()
            Button("Delete", role: .destructive) { tasks.delete(task) }
        }
        .transition(.opacity)
    }

    /// "3 of 7 today" under a bar: glowing on glass, hatched on paper, or `[###----] 3/7` in a console.
    private func progressView(_ progress: (done: Int, of: Int)) -> some View {
        let fraction = Double(progress.done) / Double(max(progress.of, 1))
        return Group {
            if look == .console {
                let cells = 7
                let filled = Int((fraction * Double(cells)).rounded())
                let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: cells - filled)
                Text("[\(bar)] \(progress.done)/\(progress.of)")
                    .themeFont(.mono, size: 11)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressBar(fraction: fraction, hatched: look == .cards)
                        .frame(height: look == .cards ? 7 : 4)
                    Text("\(progress.done) of \(progress.of) today")
                        .themeFont(.body, size: 10.5)
                        .foregroundStyle(.themeSecondary)
                        .lineLimit(1)
                }
            }
        }
        .animation(moving, value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Done today")
        .accessibilityValue("\(progress.done) of \(progress.of)")
    }

    private func dropZone(lit: Bool) -> some View {
        let text = Text(look == .console ? "[drop to finish]" : "Drop to finish")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                ThemeSymbol("checkmark")
                text
            }
            text
            ThemeSymbol("checkmark")
        }
        .themeFont(look.detailRole, size: 11)
        .lineLimit(1)
        .foregroundStyle(lit ? ThemeStyle.themeInk : .themeSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { slot(lit: lit) }
        .accessibilityHidden(true)  // the column takes the drop
    }

    // MARK: Adding

    /// The + field at the top of a column: plain words, read as they're typed. Today adds for today
    /// and a list to itself, unless the words name a date or a list.
    private func addField(_ column: TaskColumn, now: Date) -> some View {
        let parsed = draft.trimmingCharacters(in: .whitespaces).isEmpty ? nil : TaskDraft.parse(draft)
        return VStack(alignment: .leading, spacing: 3) {
            TextField("Add to \(column.title)", text: $draft, prompt: theme.prompt("Pay rent fri 9am #Home", .caption))
                .textFieldStyle(.plain)
                .themeFont(look.detailRole, size: 12)
                .focused($typing)
                .takesKeyboard(true)
                .onSubmit { submit(to: column, now: now) }
                .onExitCommand {
                    adding = nil
                    draft = ""
                }
                .onChange(of: typing) { _, isTyping in
                    if !isTyping, draft.isEmpty { adding = nil }
                }
                .onAppear { Task { @MainActor in typing = true } }  // once the field is on screen
                .padding(.horizontal, 7)
                .frame(height: 24)
                .themePlatter(0.1, in: RoundedRectangle(cornerRadius: look.cardRadius(theme), style: .continuous))
            if let parsed, parsed.hasDetails {
                Text(summary(of: parsed))
                    .themeFont(look.detailRole, size: 10)
                    .foregroundStyle(.themeSecondary)
                    .lineLimit(1)
            }
        }
        .transition(.opacity)
    }

    /// What quick add has understood besides the title: "Fri 9:00 AM · High · #Home".
    private func summary(of draft: TaskDraft) -> String {
        [
            draft.due.map { DueLabel.text(for: $0, hasTime: draft.hasTime) }, draft.repeats?.name,
            draft.priority == .none ? nil : draft.priority.name, draft.list.map { "#\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func submit(to column: TaskColumn, now: Date) {
        var day: Date?
        var list: String?
        switch column.kind {
        case .today: day = now
        case .list(let id): list = id
        case .upcoming, .done: break  // Upcoming takes it as typed, undated if it names no day
        }
        var added = false
        withAnimation(moving) { added = tasks.add(draft, day: day, list: list) }
        if added { draft = "" }  // the field stays open for the next one
    }

    // MARK: Moving

    /// Drops the dragged card. The text must be its title, so a drag that ended somewhere else
    /// can't move it on a later drop.
    private func drop(_ text: String?, in spot: TaskSpot, before target: TaskItem?) -> Bool {
        defer {
            dragging = nil
            over = nil
        }
        guard let task = dragging, text == task.title, task.id != target?.id else { return false }
        land(task, in: spot, before: target)
        return true
    }

    /// Done ticks the card and it settles at the top of Done; anywhere else it moves there.
    private func land(_ task: TaskItem, in spot: TaskSpot, before target: TaskItem? = nil) {
        if spot == .done {
            if task.completed == nil { tick(task) }
        } else {
            withAnimation(moving) { tasks.move(task, to: spot, before: target) }
        }
    }

    private func spot(for kind: TaskColumn.Kind, _ task: TaskItem) -> TaskSpot {
        switch kind {
        case .today: .today
        case .upcoming: tasks.upcomingSpot(for: task)
        case .list(let id): .list(id)
        case .done: .done
        }
    }

    private func mark(_ landing: Landing, _ targeted: Bool) {
        withAnimation(opening) {
            if targeted {
                // A card or a day inside a column outranks the column around it.
                if case .column = landing, let over, over != landing { return }
                over = landing
            } else if over == landing {
                over = nil
            }
        }
    }

    /// The dragged card comes from above `task` in its run, so it would land below it.
    private func fromAbove(_ task: TaskItem, in run: TaskRun) -> Bool {
        let ids = run.tasks.map(\.id)
        guard let from = dragging.flatMap({ ids.firstIndex(of: $0.id) }) else { return false }
        return from < (ids.firstIndex(of: task.id) ?? 0)
    }

    /// One place up or down, for VoiceOver.
    private func step(_ task: TaskItem, by offset: Int, in run: TaskRun) {
        guard let index = run.tasks.firstIndex(where: { $0.id == task.id }), run.tasks.indices.contains(index + offset)
        else { return }
        land(task, in: run.spot, before: run.tasks[index + offset])
    }

    /// The arrows choose a card along its column and across to the next, and open it; with ⌘, ← and
    /// → move it.
    private func step(_ key: KeyEquivalent, command: Bool) -> KeyPress.Result {
        guard renaming == nil, adding == nil else { return .ignored }
        let columns = tasks.columns()
        let lanes = columns.map(\.tasks)
        guard let id = chosen, let x = lanes.firstIndex(where: { $0.contains { $0.id == id } }),
            let y = lanes[x].firstIndex(where: { $0.id == id })
        else {
            choose(lanes.first { !$0.isEmpty }?.first?.id)
            return chosen == nil ? .ignored : .handled
        }
        let across = key == .leftArrow ? -1 : key == .rightArrow ? 1 : 0
        if across == 0 {
            let lane = lanes[x]
            choose(lane[min(max(y + (key == .upArrow ? -1 : 1), 0), lane.count - 1)].id)
        } else if command {
            guard columns.indices.contains(x + across) else { return .handled }
            land(lanes[x][y], in: spot(for: columns[x + across].kind, lanes[x][y]))
        } else {
            var to = x + across
            while lanes.indices.contains(to), lanes[to].isEmpty { to += across }
            guard lanes.indices.contains(to) else { return .handled }
            choose(lanes[to][min(y, lanes[to].count - 1)].id)
        }
        return .handled
    }

    /// Chooses a card and opens it, folding the one open before; nil chooses none.
    private func choose(_ id: TaskItem.ID?) {
        chosen = id
        withAnimation(moving) { expanded = id }
    }

    /// Chooses a card and opens it, or folds it when it's the open one.
    private func toggle(_ id: TaskItem.ID) {
        chosen = id
        withAnimation(moving) { expanded = expanded == id ? nil : id }
    }

    /// A click on a card opens or folds it; a second one on it within the double-click time renames
    /// it, leaving it as the first click did.
    private func click(_ task: TaskItem) {
        let now = Date.now
        if let last = lastClick, last.id == task.id, now.timeIntervalSince(last.at) < NSEvent.doubleClickInterval {
            lastClick = nil
            renaming = task.id
        } else {
            lastClick = (task.id, now)
            toggle(task.id)
        }
    }

    /// Space: ticks the chosen card, or opens a done one again.
    private func tickChosen() -> KeyPress.Result {
        guard renaming == nil, adding == nil, let id = chosen else { return .ignored }
        if let task = tasks.tasks.first(where: { $0.id == id }) {
            tick(task)
        } else if let task = tasks.completed.first(where: { $0.id == id }) {
            reopen(task)
        }
        return .handled
    }

    /// Shows the check for a beat, then moves the task to Done.
    private func tick(_ task: TaskItem) {
        ticking.insert(task.id)
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 350))
            withAnimation(moving) { tasks.complete(task) }
            ticking.remove(task.id)
        }
    }

    private func reopen(_ task: TaskItem) {
        withAnimation(moving) { tasks.reopen(task) }
    }

    private func boxColor(_ task: TaskItem) -> Color {
        task.color.map { theme.listInk($0.color) } ?? theme.color(.ink)
    }

    @ViewBuilder private var noticeView: some View {
        if let notice = tasks.notice {
            ThemeLabel(notice, symbol: "checkmark.circle")
                .themeFont(look.detailRole, size: 11, weight: .medium)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .themePlatter(0.14, in: Capsule())
                .background(theme.surface.color.color, in: Capsule())  // over the cards, opaque
                .padding(.bottom, 4)
                .transition(.opacity)
        }
    }
}

/// Where a dragged card would land: before a card, at the end of a run, or in a column.
private enum Landing: Hashable {
    case card(TaskItem.ID)
    case run(TaskSpot)
    case column(TaskColumn.Kind)
}

/// How the board draws in a theme: soft glass columns of frosted cards; on a light sheet, index cards
/// with ink borders between hairlines; and where the theme draws its tabs as a terminal, boxed
/// columns of boxed cards, the chosen one inverted, with 24-hour times.
private enum TasksLook {
    case glass, cards, console

    init(_ theme: Theme) {
        if theme.skin(.tabRow) == "terminal" {
            self = .console
        } else {
            self = theme.appearance == .light ? .cards : .glass
        }
    }

    /// A card's title: the display face on an index card, the console's own face, or the body.
    var titleRole: Theme.Fonts.Role {
        switch self {
        case .glass: .body
        case .cards: .display
        case .console: .mono
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .glass: 13
        case .cards: 14
        case .console: 12
        }
    }

    var detailRole: Theme.Fonts.Role { self == .console ? .mono : .body }

    /// A boxed or glass column pads all round; paper columns run to the top and bottom of the sheet.
    var columnInset: EdgeInsets {
        let vertical: CGFloat = self == .cards ? 0 : 7
        return EdgeInsets(top: vertical, leading: 7, bottom: vertical, trailing: 7)
    }

    /// The theme's own corners for its controls; an index card's are nearly square.
    func cardRadius(_ theme: Theme) -> CGFloat {
        let own = theme.controls?.radius.map { CGFloat($0) }
        switch self {
        case .glass: return own ?? 10
        case .cards: return min(own ?? 2, 2)
        case .console: return own ?? 0
        }
    }

    func columnRadius(_ theme: Theme) -> CGFloat {
        theme.controls?.radius.map { $0 == 0 ? 0 : CGFloat($0) + 5 } ?? 15
    }

    /// Square boxes where the theme's controls are square.
    func squareBoxes(_ theme: Theme) -> Bool { theme.controls?.radius == 0 }
}

/// A day heading's type: small capitals on glass, the display face on paper, a comment in a console.
private struct RunHeadFont: ViewModifier {
    let look: TasksLook

    func body(content: Content) -> some View {
        switch look {
        case .glass:
            content.themeFont(.body, size: 10.5, weight: .bold).textCase(.uppercase).tracking(0.6)
        case .cards:
            content.themeFont(.display, size: 13, weight: .semibold)
        case .console:
            content.themeFont(.mono, size: 11)
        }
    }
}

extension Theme {
    /// A list's color, or a warning's, as it reads on this sheet: on a light one, worked toward the
    /// ink like a pigment.
    fileprivate func listInk(_ color: Color) -> Color {
        guard appearance == .light else { return color }
        if #available(macOS 15, *) { return color.mix(with: self.color(.ink), by: 0.3) }
        return color
    }

    /// The line around boxed cards and columns: the theme's own, or the secondary ink.
    fileprivate var taskLine: Color { controls?.lineColor?.color ?? color(.secondary) }
}

/// One open task: its box, its title with any priority, and its due time and list. The task due now
/// grows Done and Snooze. Opened, it shows all of it: the whole title, its notes, when it's due in
/// full, its list, and its actions. Hovering shows its menu; renaming swaps the title for a field.
private struct TaskCard: View {
    let tasks: TasksFeature
    let task: TaskItem
    let now: Date
    /// The run it's in: in Today or under a day, the due time is enough.
    let spot: TaskSpot
    var chosen = false
    var dueNow = false
    var expanded = false
    var ticked = false
    var showsList = false
    @Binding var renaming: TaskItem.ID?
    var tick: () -> Void = {}

    @State private var title = ""
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme

    private var look: TasksLook { TasksLook(theme) }
    private var editing: Bool { renaming == task.id }
    /// Chosen and not being renamed: the theme's selection shows.
    private var lit: Bool { chosen && !editing }
    /// The chosen card's mark fills it, rather than underlining its title. The card due now keeps
    /// its own look, ringed instead.
    private var filled: Bool {
        lit && !dueNow && [.pill, .accent, .block].contains(theme.controls?.selection ?? .pill)
    }
    /// On an accent or block selection, everything on the card takes the accent's own ink.
    private var inverted: Bool { lit && !dueNow && theme.selectsOnAccent }
    private var tint: Color? { task.color.map { theme.listInk($0.color) } }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: look.cardRadius(theme), style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 7) {
                Button(action: tick) {
                    CheckBox(
                        done: ticked, color: boxInk, square: look.squareBoxes(theme),
                        mark: inverted ? theme.color(.accent) : theme.surface.color.color,
                        backing: look == .cards ? theme.surface.color.color : nil
                    )
                    .frame(width: 15, height: 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityLabel("Complete \(task.title)")
                VStack(alignment: .leading, spacing: 3) {
                    if editing { field } else { titleLine }
                    if expanded { fullDetails } else { details }
                }
                Spacer(minLength: 0)
            }
            // The card's full width, so they fit the narrowest column.
            if dueNow, !editing { nowButtons }
            if expanded, !editing { actions }
        }
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .padding(.vertical, 6)
        .background { backdrop(shape) }
        .overlay {
            if lit, dueNow || (look == .glass && filled && theme.controls?.selection ?? .pill == .pill) {
                shape.strokeBorder(.themeInk.opacity(0.5), lineWidth: 1.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Opened, the menu is in its actions, clear of the title's lines.
            if hovering, !editing, !expanded { more }
        }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
        .accessibilityAction(named: "Rename") { renaming = task.id }
        .accessibilityAction(named: "Block Time in Calendar") { tasks.blockTime(for: task) }
    }

    /// The title on one line; opened, on as many as it takes. Any priority marks lead its first
    /// line, so the others run the card's width.
    private var titleLine: some View {
        let marks = Text(task.priority.marks).fontWeight(.heavy).foregroundStyle(priorityInk)
        return (task.priority == .none ? Text(task.title) : Text("\(marks) \(task.title)"))
            .lineLimit(expanded ? nil : 1)
            .fixedSize(horizontal: false, vertical: expanded)
            .background {
                // An underline or dot selection marks the title, as on a printed page.
                if lit, !filled, !dueNow { SelectionMark().padding(.horizontal, -4).offset(y: 2) }
            }
            .themeFont(look.titleRole, size: look.titleSize)
            .themeSelectionInk(inverted, unlit: 1)
            .opacity(ticked ? 0.5 : 1)
    }

    /// The due time (or day), whether it repeats, and the list, when there are any.
    @ViewBuilder private var details: some View {
        let due = dueText
        // The card due now glows in its list's color in place of naming it.
        let list = showsList && !dueNow ? task.listTitle : nil
        if due != nil || list != nil || task.repeats {
            HStack(spacing: 6) {
                if let due {
                    // When it's due outranks its list, which truncates first. Where it's narrow, the
                    // card due now drops its time.
                    Group {
                        if dueNow {
                            ViewThatFits(in: .horizontal) {
                                Text(due)
                                Text(look == .console ? "due now" : "Due now")
                            }
                        } else {
                            Text(due)
                        }
                    }
                    .fontWeight(dueNow ? .bold : nil)
                    .foregroundStyle(dueInk)
                    .layoutPriority(1)
                }
                if task.repeats { ThemeSymbol("repeat") }
                if let list { listTag(list) }
            }
            .themeFont(look.detailRole, size: 11)
            .foregroundStyle(inverted ? ThemeStyle.themeOnAccent : .themeSecondary)
            .lineLimit(1)
            .frame(height: 14)
        }
    }

    /// "3:30 PM" in its own day's run, "Wed" or "Wed 3:30 PM" from another day, "Due now · 3:30 PM";
    /// a console's are 24-hour and lowercase.
    private var dueText: String? {
        guard let due = task.due else { return nil }
        let console = look == .console
        let time = taskClock(due, twentyFour: console)
        if dueNow { return console ? "due now \(time)" : "Due now · \(time)" }
        let calendar = Calendar.current
        let ownDay: Bool =
            switch spot {
            case .today: calendar.isDate(due, inSameDayAs: now)
            case .day(let day?): calendar.isDate(due, inSameDayAs: day)
            default: false
            }
        if ownDay, !task.hasTime { return nil }
        let text = ownDay ? time : taskDayName(due, now: now) + (task.hasTime ? " \(time)" : "")
        return console ? text.lowercased() : text
    }

    /// The open card's details, wrapped rather than cut: its notes, when it's due in full and
    /// whether it repeats, and its list.
    private var fullDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let notes = task.notes { Text(notes) }
            if let due = task.due {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(fullDue(due)).fontWeight(dueNow ? .bold : nil).foregroundStyle(dueInk)
                    if task.repeats { ThemeSymbol("repeat") }
                }
            }
            if let list = task.listTitle { listTag(list) }
        }
        .themeFont(look.detailRole, size: 11)
        .foregroundStyle(inverted ? ThemeStyle.themeOnAccent : .themeSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
    }

    /// "Wed, Nov 18, 3:30 PM", with the year when it isn't this one's; a console's is 24-hour and
    /// lowercase.
    private func fullDue(_ due: Date) -> String {
        var format = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        if !Calendar.current.isDate(due, equalTo: now, toGranularity: .year) { format = format.year() }
        guard look == .console else { return due.formatted(task.hasTime ? format.hour().minute() : format) }
        return (due.formatted(format) + (task.hasTime ? " \(taskClock(due, twentyFour: true))" : "")).lowercased()
    }

    /// The open card's actions, under its title: rename, block time in Calendar, and the rest of its
    /// menu.
    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                renaming = task.id
            } label: {
                ThemeSymbol("pencil").frame(width: 18, height: 18)
            }
            .help("Rename")
            .accessibilityLabel("Rename")
            Button {
                tasks.blockTime(for: task)
            } label: {
                ThemeSymbol("calendar.badge.plus").frame(width: 18, height: 18)
            }
            .help("Block \(tasks.blockMinutes) min in Calendar")
            .accessibilityLabel("Block \(tasks.blockMinutes) minutes in Calendar")
            Menu {
                menuItems
            } label: {
                ThemeSymbol("ellipsis.circle").frame(width: 18, height: 18)
            }
            // A button menu draws its label as the buttons beside it do, in the theme's icon and ink,
            // where a borderless one hands it to AppKit at the icon's own size.
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More")
        }
        .buttonStyle(PressableButtonStyle())
        .themeFont(.body, size: 12)
        .foregroundStyle(inverted ? ThemeStyle.themeOnAccent : .themeSecondary)
        .padding(.leading, 18)  // under the title, past the box
        .transition(.opacity)
    }

    private var dueInk: Color {
        if inverted { return theme.color(.onAccent) }
        if dueNow {
            // The list's own color; on paper, the ink without one, as an accent may be too light to read.
            switch look {
            case .glass: return tint ?? theme.color(.accent)
            case .cards: return tint ?? theme.color(.ink)
            case .console: return theme.color(.ink)
            }
        }
        if task.isOverdue(now: now) { return theme.listInk(.red) }  // overdue: red in every theme
        return theme.color(.secondary)
    }

    /// Reminders' own orange, or a console's ink.
    private var priorityInk: Color {
        if inverted { return theme.color(.onAccent) }
        return look == .console ? theme.color(.ink) : theme.listInk(.orange)
    }

    private var boxInk: Color {
        if inverted { return theme.color(.onAccent) }
        if look == .console { return theme.color(.ink) }
        return tint ?? theme.color(.ink)
    }

    /// The list in its color; small capitals on an index card, a tag in a console.
    @ViewBuilder private func listTag(_ list: String) -> some View {
        let color = inverted ? theme.color(.onAccent) : tint ?? theme.color(.secondary)
        switch look {
        case .glass:
            Text(list).fontWeight(.semibold).foregroundStyle(color)
        case .cards:
            Text(list.uppercased()).themeFont(.body, size: 9.5, weight: .bold).tracking(0.8).foregroundStyle(color)
        case .console:
            Text("#\(list.lowercased().filter { !$0.isWhitespace })")
        }
    }

    /// Done and Snooze, Snooze shortening down to its icon where the column is narrow.
    private var nowButtons: some View {
        let minutes = TasksFeature.snoozeMinutes
        let console = look == .console
        return ViewThatFits(in: .horizontal) {
            nowButtons { Text(console ? "[snooze \(minutes)m]" : "Snooze \(minutes) min") }
            nowButtons { Text(console ? "[snooze]" : "Snooze") }
            nowButtons { Text(console ? "[+\(minutes)m]" : "+\(minutes) min") }
            nowButtons { ThemeSymbol("moon.zzz.fill") }
        }
    }

    private func nowButtons(@ViewBuilder snooze: () -> some View) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: theme.controls?.radius.map { CGFloat($0) } ?? 11, style: .continuous)
        let glass = look == .glass
        return HStack(spacing: 5) {
            Button(action: tick) {
                Text(look == .console ? "done \u{23CE}" : "Done")
                    .foregroundStyle(glass ? theme.surface.color.color : theme.color(.onAccent))
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(glass ? theme.color(.ink) : theme.color(.accent), in: shape)
            }
            .accessibilityLabel("Done")
            Button {
                tasks.snooze(task)
            } label: {
                snooze()
                    .foregroundStyle(.themeSecondary)
                    .padding(.horizontal, look == .console ? 0 : 8)
                    .frame(height: 22)
                    .themePlatter(look == .console ? 0 : 0.1, in: shape)
            }
            .help("Snooze for \(TasksFeature.snoozeMinutes) minutes")
            .accessibilityLabel("Snooze for \(TasksFeature.snoozeMinutes) minutes")
        }
        .buttonStyle(PressableButtonStyle())
        .themeFont(look.detailRole, size: 11, weight: .semibold)
        .fixedSize()
    }

    /// The card's backing: frosted glass, an index card with an offset shadow, or a box; the card
    /// due now glows in its list's color, inks its border, or lights its box.
    @ViewBuilder private func backdrop(_ shape: RoundedRectangle) -> some View {
        switch look {
        case .glass:
            if filled {
                SelectionMark(in: shape, strength: 0.13)
            } else if dueNow {
                let glow = tint ?? theme.color(.accent)
                shape.fill(
                    LinearGradient(
                        colors: [glow.opacity(0.3), glow.opacity(0.08)], startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                )
                .overlay(shape.strokeBorder(glow.opacity(0.5), lineWidth: 1))
                .shadow(color: glow.opacity(0.3), radius: 10)
            } else {
                Color.clear.themePlatter(hovering ? 0.11 : 0.08, in: shape)
            }
        case .cards:
            let hard = theme.controls?.shadow == .hard
            let line = hard ? theme.taskLine : theme.color(.ink).opacity(dueNow ? 1 : 0.45)
            let offset: CGFloat = dueNow ? 3 : 2
            ZStack {
                shape.fill(hard || dueNow ? line : theme.color(.ink).opacity(hovering ? 0.16 : 0.1))
                    .offset(x: offset, y: offset)
                shape.fill(theme.surface.color.color)
                if filled { SelectionMark(in: shape, strength: 0.1) }
                shape.strokeBorder(line, lineWidth: CGFloat(theme.controls?.line ?? 1) * (dueNow ? 1.5 : 1))
            }
        case .console:
            ZStack {
                if filled { SelectionMark(in: shape) }
                shape.strokeBorder(dueNow || hovering ? theme.color(.ink) : theme.taskLine, lineWidth: 1)
            }
            .shadow(color: dueNow ? theme.color(.accent).opacity(0.4) : .clear, radius: 6)
        }
    }

    private var more: some View {
        Menu {
            menuItems
        } label: {
            ThemeSymbol("ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .themeFont(.body, size: 11)
        .padding(5)
        .help("More")
    }

    @ViewBuilder private var menuItems: some View {
        Button("Rename") { renaming = task.id }
        Menu("Due") {
            ForEach(DueChoice.allCases) { choice in
                Button(choice.name) { tasks.setDue(task, to: choice) }
            }
        }
        Picker(
            "Priority",
            selection: Binding(get: { task.priority }, set: { tasks.setPriority(task, to: $0) })
        ) {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Text(priority == .none ? "None" : "\(priority.name) \(priority.marks)").tag(priority)
            }
        }
        .pickerStyle(.menu)
        if tasks.lists.count > 1 {
            Picker(
                "List",
                selection: Binding(get: { task.listID ?? "" }, set: { tasks.move(task, toList: $0) })
            ) {
                ForEach(tasks.lists) { list in
                    Text(list.title).tag(list.id)
                }
            }
            .pickerStyle(.menu)
        }
        Button("Block \(tasks.blockMinutes) Min in Calendar") { tasks.blockTime(for: task) }
        Divider()
        Button("Delete", role: .destructive) { tasks.delete(task) }
    }

    private var field: some View {
        TextField("Task", text: $title, prompt: theme.prompt("Task", .callout))
            .textFieldStyle(.plain)
            .themeFont(look.titleRole, size: look.titleSize)
            .focused($focused)
            .takesKeyboard(true)
            .onSubmit(commitRename)
            .onExitCommand { renaming = nil }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commitRename() }
            }
            .onAppear {
                title = task.title
                Task { @MainActor in focused = true }  // once the field is on screen
            }
    }

    private func commitRename() {
        guard renaming == task.id else { return }
        renaming = nil
        tasks.rename(task, to: title)
    }
}

/// A task's box: a ring (or a square, where the theme's controls are square) in its list's color,
/// filled with a check once done.
private struct CheckBox: View {
    let done: Bool
    let color: Color
    let square: Bool
    /// The check's color, on the filled box.
    let mark: Color
    /// Behind an open box: the card's own color, so the sheet's texture doesn't show through.
    var backing: Color?

    var body: some View {
        ZStack {
            if square { box(Rectangle()) } else { box(Circle()) }
            if done {
                ThemeSymbol("checkmark").themeFont(.body, size: 8, weight: .black).foregroundStyle(mark)
            }
        }
    }

    @ViewBuilder private func box(_ shape: some InsettableShape) -> some View {
        if done {
            shape.fill(color)
        } else {
            shape.fill(backing ?? .clear).overlay(shape.strokeBorder(color, lineWidth: 1.5))
        }
    }
}

/// Today's progress as a bar: a thin glowing line on a dark sheet, a hatched bar in a ruled box on a
/// light one.
private struct ProgressBar: View {
    let fraction: Double
    let hatched: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let ink = theme.color(.ink)
        GeometryReader { proxy in
            let width = proxy.size.width * min(max(fraction, 0), 1)
            if hatched {
                Canvas { context, size in
                    var lines = Path()
                    for x in stride(from: -size.height, through: size.width, by: 3.5) {
                        lines.move(to: CGPoint(x: x, y: size.height))
                        lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                    }
                    context.stroke(lines, with: .color(ink), lineWidth: 1.2)
                }
                .frame(width: width)
                .clipped()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
            } else {
                Capsule().fill(ink.opacity(0.14))
                    .overlay(alignment: .leading) {
                        Capsule().fill(ink).frame(width: width).shadow(color: ink.opacity(0.7), radius: 5)
                    }
            }
        }
    }
}

/// A time of day as a card shows it: "3:30 PM", or "15:30" on a 24-hour console.
private func taskClock(_ date: Date, twentyFour: Bool) -> String {
    guard twentyFour else { return date.formatted(date: .omitted, time: .shortened) }
    let time = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", time.hour ?? 0, time.minute ?? 0)
}

/// A day as a card names it: "Today", "Tomorrow", "Yesterday", "Wed" within the week, else "Jun 3".
private func taskDayName(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
    let today = calendar.startOfDay(for: now)
    switch calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0 {
    case 0: return "Today"
    case 1: return "Tomorrow"
    case -1: return "Yesterday"
    case -6...6: return date.formatted(.dateTime.weekday(.abbreviated))
    default: return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// A day's heading in Upcoming: "Tomorrow", "Mon 23" within the week, "Jun 3" after, or "No date".
private func taskDayTitle(_ spot: TaskSpot, now: Date, calendar: Calendar = .current) -> String {
    guard case .day(let day?) = spot else { return "No date" }
    let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
    if offset == 1 { return "Tomorrow" }
    guard offset < 7 else { return day.formatted(.dateTime.day().month(.abbreviated)) }
    return "\(day.formatted(.dateTime.weekday(.abbreviated))) \(calendar.component(.day, from: day))"
}

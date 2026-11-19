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

/// Music, today, the AI plans (when the build has them), and the prompter, each a card that opens its
/// tab. A theme's `cards` colors them, as Bento's paper does; otherwise they sit on its fill.
public struct HomeView: View {
    let media: MediaFeature
    let calendar: CalendarFeature
    let prompter: PrompterFeature
    /// The AI plans' card, from the GitHub build's AI Usage; nil leaves it out.
    let usage: AnyView?
    let open: (FeatureID) -> Void

    @Environment(\.theme) private var theme

    public init(
        media: MediaFeature, calendar: CalendarFeature, prompter: PrompterFeature, usage: AnyView?,
        open: @escaping (FeatureID) -> Void
    ) {
        self.media = media
        self.calendar = calendar
        self.prompter = prompter
        self.usage = usage
        self.open = open
    }

    public var body: some View {
        let cards: [(FeatureID, AnyView)] =
            [(.media, AnyView(music)), (.calendar, AnyView(today))] + (usage.map { [(FeatureID.usage, $0)] } ?? [])
            + [(.prompter, AnyView(script))]
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                self.card(index, card.0, card.1)
            }
        }
    }

    /// The card's color comes from the theme's `cards` in turn, and its words in their ink.
    private func card(_ index: Int, _ feature: FeatureID, _ content: AnyView) -> some View {
        let cards = theme.cards
        let fill = cards.map { $0.colors[index % $0.colors.count].color } ?? theme.color(.fill)
        return Button {
            open(feature)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title).themeFont(.body, .caption, weight: .semibold).opacity(0.7)
                content
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(10)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(cards?.ink.color ?? theme.color(.ink))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Open \(feature.title)")
    }

    @ViewBuilder private var music: some View {
        if let now = media.nowPlaying {
            HStack(spacing: 8) {
                if let artwork = media.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(now.title).themeFont(.display, size: 13, weight: .semibold)
                    if let artist = now.artist { Text(artist).themeFont(.body, size: 11).opacity(0.7) }
                }
            }
        } else {
            Text("Nothing playing").themeFont(.body, size: 12).opacity(0.7)
        }
    }

    /// The next event still to come today, and how many tasks are due.
    @ViewBuilder private var today: some View {
        if let next = calendar.events.first(where: { !$0.isAllDay && $0.end > .now }) {
            Text(next.title).themeFont(.display, size: 13, weight: .semibold)
            Text(next.start, format: .dateTime.hour().minute()).themeFont(.body, size: 11).opacity(0.7)
        } else {
            Text("Nothing else today").themeFont(.body, size: 12).opacity(0.7)
        }
        let due = calendar.dueTasks.count
        Text(due == 0 ? "No tasks due" : due == 1 ? "1 task due" : "\(due) tasks due")
            .themeFont(.body, size: 11).opacity(0.7)
    }

    /// The script's first line, or how to start one.
    private var script: some View {
        let first = prompter.script.split(whereSeparator: \.isNewline).first.map(String.init)
        return Text(first ?? "No script yet").themeFont(.body, size: 12).opacity(first == nil ? 0.7 : 1)
    }
}

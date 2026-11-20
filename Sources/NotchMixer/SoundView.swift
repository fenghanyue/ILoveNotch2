// SPDX-License-Identifier: MIT
import AppKit
import NotchFeatures
import NotchTheme
import SwiftUI

/// The Sound tab, a mixing desk: a channel strip for each app playing sound (its icon and name, a
/// fader, the value, and a mute key), then after a rule the master: Output or Input, that device's
/// fader, and the devices to play through or record from. Drag a fader or scroll over a strip to
/// set it, double-click an app's fader for 100%, click the speaker to mute. More apps than fit
/// scroll sideways. There are no level meters: the mixer's taps don't measure what they carry.
public struct SoundView: View {
    let mixer: Mixer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    public init(mixer: Mixer) {
        self.mixer = mixer
    }

    public var body: some View {
        GeometryReader { proxy in
            // Names fit in a taller notch, and so do the devices' connections; a short one slims the
            // strips and drops their values, so a third app peeks in to show the row scrolls.
            let names = proxy.size.height >= 150
            let slim = proxy.size.height < 120
            HStack(spacing: 0) {
                strips(names: names, slim: slim)
                rule.padding(.horizontal, slim ? 6 : 9)
                MasterSection(mixer: mixer, slim: slim, details: names)
                    .frame(width: slim ? 158 : 172)
            }
        }
        .overlay(alignment: .top) {
            if mixer.needsPermission {
                permission.transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mixer.needsPermission)
        .onAppear { mixer.appeared() }
        .onDisappear { mixer.disappeared() }
    }

    @ViewBuilder private func strips(names: Bool, slim: Bool) -> some View {
        if mixer.apps.isEmpty {
            empty.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(mixer.apps) { app in
                        ChannelStrip(mixer: mixer, app: app, names: names, slim: slim)
                            .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxHeight: .infinity)
            }
            .scrollIndicators(.never)
            .fadingEdges(.horizontal, length: 6)
            // A new app's strip slides in from the left; with Reduce Motion it fades in.
            .animation(.easeOut(duration: 0.25), value: mixer.apps.map(\.id))
        }
    }

    /// Between the apps and the master, drawn like the theme's lines: dashed in Terminal.
    private var rule: some View {
        VLine()
            .stroke(
                theme.controls?.lineColor?.color ?? theme.color(.ink).opacity(0.12),
                style: StrokeStyle(lineWidth: 1, dash: theme.seekBar.rest == .dashed ? [4, 3] : [])
            )
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    /// What fits under a fader or in the device list: "AirPods Pro" out of "Niyam's AirPods Pro",
    /// "Speakers" out of "MacBook Pro Speakers", "iPhone Microphone" out of "Niyam's iPhone
    /// Microphone".
    nonisolated static func shortName(_ name: String) -> String {
        if let airPods = name.range(of: "AirPods") { return String(name[airPods.lowerBound...]) }
        if name.hasSuffix("Headphones") { return "Headphones" }
        var name = name
        if let owner = name.range(of: "'s ") ?? name.range(of: "’s ") { name = String(name[owner.upperBound...]) }
        let macs = ["MacBook Pro ", "MacBook Air ", "MacBook ", "iMac ", "Mac mini ", "Mac Studio ", "Mac Pro "]
        if let mac = macs.first(where: { name.hasPrefix($0) }) { name = String(name.dropFirst(mac.count)) }
        return name
    }

    /// A speaker with as many waves as the level, like the volume in the closed notch.
    static func speaker(_ level: Double) -> String {
        switch level {
        case ..<0.005: "speaker.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    private var empty: some View {
        VStack(spacing: 5) {
            ThemeSymbol("waveform")
                .themeFont(.body, size: 16, weight: .medium)
                .foregroundStyle(.themeInk.opacity(0.45))
            Text("Apps playing sound show up here")
                .themeFont(.body, size: 10)
                .foregroundStyle(.themeInk.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(width: 92)
    }

    private var permission: some View {
        HStack(spacing: 6) {
            ThemeSymbol("exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("Allow System Audio Recording to change app volumes").lineLimit(1)
            Button("Open Settings") { NSWorkspace.shared.open(.privacySettings("Privacy_AudioCapture")) }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
        }
        .themeFont(.body, .caption2)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(theme.surface.color.color.opacity(0.8), in: Capsule())
        .overlay(Capsule().strokeBorder(.themeInk.opacity(0.15), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// One app's channel: its icon and name, a fader, the value, and a mute key, with a lamp while it
/// plays. Hovered, it lights up the way the theme marks a selection: brighter in Black, its name
/// underlined in Paper, its name inverted and its box lit in Terminal.
private struct ChannelStrip: View {
    let mixer: Mixer
    let app: MixerApp
    let names: Bool
    let slim: Bool

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let level = mixer.level(of: app.id)
        let muted = mixer.isMuted(app.id)
        let percent = Int((level * 100).rounded())
        VStack(spacing: slim ? 3 : 5) {
            icon(muted: muted)
            if names { name }
            VerticalFader(level: level, muted: muted, enabled: true, reset: { mixer.setLevel(1, of: app.id) }) {
                mixer.setLevel($0, of: app.id)
            }
            if !slim {
                Text(muted ? "Muted" : "\(percent)%")
                    .themeFont(.body, size: 10)
                    .monospacedDigit()
                    .foregroundStyle(.themeSecondary)
            }
            MuteKey(muted: muted, symbol: "speaker.wave.2.fill", mutedSymbol: "speaker.slash.fill") {
                mixer.toggleMute(app.id)
            }
            .help(muted ? "Unmute \(app.name)" : "Mute \(app.name)")
        }
        .padding(.vertical, slim ? 4 : 7)
        .frame(width: slim ? 46 : 54)
        .background { backing }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.themeAccent)
                .frame(width: 4, height: 4)
                .padding(5)
                .opacity(app.isPlaying && !muted ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .background(ScrollCatcher { mixer.setLevel(mixer.level(of: app.id) + $0, of: app.id) })
        .contextMenu {
            Button(muted ? "Unmute" : "Mute") { mixer.toggleMute(app.id) }
            if mixer.isAdjusted(app.id) { Button("Reset to 100%") { mixer.reset(app.id) } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue(muted ? "Muted" : "\(percent)%")
        .accessibilityAdjustableAction { direction in
            mixer.setLevel(level + (direction == .increment ? 0.05 : -0.05), of: app.id)
        }
        .accessibilityAction(named: muted ? "Unmute" : "Mute") { mixer.toggleMute(app.id) }
    }

    /// The app's own icon: glowing in its color on a dark sheet, framed like a print where the
    /// theme outlines its controls.
    private func icon(muted: Bool) -> some View {
        let framed = theme.controls?.style == .outline
        let glows = theme.appearance == .dark && !framed
        let side: CGFloat = (slim ? 20 : 24) - (framed ? 4 : 0)
        return Image(nsImage: mixer.icon(for: app))
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .saturation(muted ? 0 : 1)
            .opacity(muted ? 0.45 : 1)
            .shadow(color: glows ? (mixer.tint(for: app) ?? theme.color(.ink)).opacity(0.45) : .clear, radius: 6)
            .padding(framed ? 2 : 0)
            .overlay {
                if framed {
                    let line = theme.controls?.lineColor?.color ?? theme.color(.ink).opacity(0.4)
                    RoundedRectangle(cornerRadius: min(theme.controls?.radius ?? 6, 6), style: .continuous)
                        .strokeBorder(line, lineWidth: 1)
                }
            }
    }

    private var name: some View {
        let marked = hovering && theme.marksName
        return Text(app.name)
            .themeFont(.body, size: 9.5, weight: .semibold)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .padding(.bottom, theme.controls?.selection == .underline ? 2 : 0)
            .themeSelectionInk(marked, unlit: 0.8)
            .background {
                if marked { SelectionMark(in: RoundedRectangle(cornerRadius: 3, style: .continuous)) }
            }
    }

    /// A soft platter in most themes, lit while hovered; dotted rules between the strips in a theme
    /// that underlines its selection, as on a printed desk.
    @ViewBuilder private var backing: some View {
        if theme.controls?.selection == .underline {
            VLine()
                .stroke(.themeInk.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 2)
        } else {
            let shape = RoundedRectangle(cornerRadius: theme.controls?.radius ?? 14, style: .continuous)
            Color.clear
                .themePlatter(hovering ? 0.1 : 0.04, in: shape)
                .overlay {
                    if hovering {
                        shape.strokeBorder(
                            .themeInk.opacity(theme.controls?.style == .outline ? 1 : 0.14), lineWidth: 1)
                    }
                }
        }
    }
}

/// The master, after the apps: Output or Input on top, then the device's fader with its value and a
/// mute key beside the devices to play through or record from, the current one carrying the
/// theme's selection mark. Input turns the fader into the microphone's gain.
private struct MasterSection: View {
    let mixer: Mixer
    let slim: Bool
    /// Room for the list's header and each device's connection.
    let details: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @State private var direction = SoundDirection.output
    @Namespace private var selection

    private var device: DeviceLevel? { direction == .output ? mixer.output : mixer.input }

    var body: some View {
        let devices = direction == .output ? mixer.outputs : mixer.inputs
        let current = device?.id
        VStack(spacing: slim ? 4 : 6) {
            switcher
            HStack(alignment: .top, spacing: slim ? 4 : 6) {
                master.frame(width: slim ? 42 : 48)
                VStack(alignment: .leading, spacing: 2) {
                    if details { header }
                    ScrollView(.vertical) {
                        VStack(spacing: 2) {
                            ForEach(devices) { item in
                                DeviceButton(
                                    device: item, current: item.id == current, details: details, selection: selection
                                ) { mixer.choose(item, for: direction) }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .fadingEdges(.vertical, length: 6)
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: current)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: devices)
    }

    /// Output and Input, the chosen one marked as the theme marks a selection; in a theme that
    /// underlines it, the pair sits on a hairline instead of a platter.
    private var switcher: some View {
        let underline = theme.controls?.selection == .underline
        return HStack(spacing: 0) {
            segment(.output, title: "Output")
            segment(.input, title: "Input")
        }
        .padding(underline ? 0 : 2)
        .background {
            if underline {
                Rectangle().fill(.themeInk.opacity(0.25)).frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                Color.clear.themePlatter(0.07, in: Capsule())
            }
        }
    }

    private func segment(_ kind: SoundDirection, title: String) -> some View {
        let chosen = direction == kind
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { direction = kind }
        } label: {
            Text(title)
                .themeFont(.body, size: 10.5, weight: .semibold)
                .themeSelectionInk(chosen, unlit: 0.55)
                .frame(maxWidth: .infinity)
                .frame(height: slim ? 16 : 19)
                .background {
                    if chosen { SelectionMark().matchedGeometryEffect(id: "segment", in: selection) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(kind == .output ? "Where sound plays" : "Where sound comes in")
        .accessibilityLabel(kind == .output ? "Output devices" : "Input devices")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The device's level in the theme's display face, its fader, and its mute key.
    private var master: some View {
        let output = direction == .output
        let level = device?.level ?? 0
        let muted = device?.isMuted ?? false
        let percent = Int((level * 100).rounded())
        return VStack(spacing: slim ? 3 : 4) {
            Text(device == nil ? "–" : "\(percent)%")
                .themeFont(.display, size: slim ? 13 : 17, weight: .bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(muted ? 0.45 : 1)
            VerticalFader(level: level, muted: muted, enabled: device?.hasVolume ?? false) {
                mixer.setDeviceLevel($0, for: direction)
            }
            if !slim {
                Text(output ? "Master" : "Gain")
                    .themeFont(.body, size: 9.5)
                    .foregroundStyle(.themeSecondary)
            }
            MuteKey(
                muted: muted, symbol: output ? SoundView.speaker(level) : "mic.fill",
                mutedSymbol: output ? "speaker.slash.fill" : "mic.slash.fill"
            ) { mixer.toggleDeviceMute(direction) }
            .disabled(device == nil)
            .help(muted ? "Unmute" : "Mute")
        }
        .background(
            ScrollCatcher { step in
                guard let device, device.hasVolume else { return }
                mixer.setDeviceLevel(device.level + step, for: direction)
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(output ? "Output volume" : "Input volume")
        .accessibilityValue(muted ? "Muted" : "\(percent)%")
        .accessibilityAdjustableAction { change in
            mixer.setDeviceLevel(min(max(level + (change == .increment ? 0.05 : -0.05), 0), 1), for: direction)
        }
        .accessibilityAction(named: muted ? "Unmute" : "Mute") { mixer.toggleDeviceMute(direction) }
    }

    /// A theme with a light sheet and a display face of its own sets it as a title (Paper's serif);
    /// the rest as a small label.
    private var header: some View {
        let titled = theme.appearance == .light && !theme.fonts.display.isSystem
        return Text(direction == .output ? "Play through" : "Record from")
            .themeFont(.display, size: titled ? 13 : 9.5, weight: .semibold)
            .textCase(titled ? nil : .uppercase)
            .tracking(titled ? 0 : 0.5)
            .foregroundStyle(titled ? .themeInk : .themeSecondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
    }
}

/// A device to play through or record from: its kind, its name, and how it connects. The current
/// one carries the theme's selection mark (Black's lit pill, Paper's underline, Terminal's block),
/// which slides to the one you pick.
private struct DeviceButton: View {
    let device: SoundDevice
    let current: Bool
    let details: Bool
    let selection: Namespace.ID
    let choose: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let underline = theme.controls?.selection == .underline
        // Black's pill glows faintly in the accent, as the chosen device does in Control Center.
        let glows = current && theme.appearance == .dark && !theme.marksName && theme.controls == nil
        Button(action: choose) {
            HStack(spacing: details ? 7 : 5) {
                ThemeSymbol(device.symbol)
                    .themeFont(.body, size: 11.5, weight: .semibold)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SoundView.shortName(device.name))
                        .themeFont(.body, size: 11, weight: .semibold)
                        .padding(.bottom, underline ? 2 : 0)
                        .background {
                            if current && underline {
                                SelectionMark().matchedGeometryEffect(id: "device", in: selection)
                            }
                        }
                    if details, let connection = device.connection {
                        Text(connection).themeFont(.body, size: 9.5).opacity(0.7)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .themeSelectionInk(current, unlit: hovering ? 0.85 : 0.65)
            .padding(.horizontal, details ? 7 : 5)
            .frame(height: details ? 32 : 22)
            .background {
                if current && !underline {
                    SelectionMark(in: shape, strength: 0.14)
                        .shadow(color: glows ? theme.color(.accent).opacity(0.3) : .clear, radius: 10)
                        .matchedGeometryEffect(id: "device", in: selection)
                } else if hovering {
                    Color.clear.themePlatter(0.06, in: shape)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(device.name)
        .accessibilityLabel(device.connection.map { "\(device.name), \($0)" } ?? device.name)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// A desk fader: a cap that slides on a line and fills it below, in the theme's look (`FaderCap`),
/// over ticks every 10% on a printed sheet. Drag or click along it; double-click it for `reset`. A
/// level set elsewhere glides there in 0.15 s, unless Reduce Motion is on.
private struct VerticalFader: View {
    let level: Double
    let muted: Bool
    let enabled: Bool
    var reset: (() -> Void)?
    let set: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @State private var dragging = false

    private static let cap = CGSize(width: 22, height: 12)

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.height - Self.cap.height, 1)
            let shown = min(max(level, 0), 1)
            ZStack(alignment: .bottom) {
                if theme.appearance == .light, theme.faderCap == .outlined {
                    Ticks()
                        .stroke(.themeInk.opacity(0.5), lineWidth: 1)
                        .frame(width: 5)
                        .padding(.vertical, Self.cap.height / 2)
                        .offset(x: 8)
                }
                track
                fill.frame(width: 4, height: Self.cap.height / 2 + shown * travel)
                cap.frame(width: Self.cap.width, height: Self.cap.height).offset(y: -shown * travel)
            }
            .frame(width: Self.cap.width)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(dragging || reduceMotion ? nil : .easeOut(duration: 0.15), value: level)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        set(min(max(1 - (drag.location.y - Self.cap.height / 2) / travel, 0), 1))
                    }
                    .onEnded { _ in dragging = false },
                isEnabled: enabled
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { reset?() }, including: reset == nil ? .subviews : .all)
        }
        .frame(minHeight: 24)
        .opacity(enabled ? 1 : 0.5)
    }

    @ViewBuilder private var track: some View {
        if theme.faderCap == .lit {
            Capsule().fill(.themeInk.opacity(0.14)).frame(width: 4)
        } else {
            Rectangle().fill(.themeSecondary).frame(width: 2)
        }
    }

    /// The level: the ink, glowing on a dark sheet, in Black; the accent elsewhere; dim while muted.
    private var fill: some View {
        let lit = theme.faderCap == .lit
        let style: ThemeStyle =
            muted ? (lit ? .themeInk.opacity(0.28) : .themeTertiary) : (lit ? .themeInk : .themeAccent)
        let glow = lit && !muted && theme.appearance == .dark
        return RoundedRectangle(cornerRadius: lit ? 2 : 0)
            .fill(style)
            .shadow(color: glow ? theme.color(.ink).opacity(0.35) : .clear, radius: 5)
    }

    @ViewBuilder private var cap: some View {
        let look = theme.faderCap
        let shape = RoundedRectangle(cornerRadius: min(theme.controls?.radius ?? 6, look == .outlined ? 2 : 6))
        Group {
            switch look {
            case .lit:
                // A shadow, dark in every theme, lifts the cap off its fill.
                shape.fill(.themeInk).shadow(color: .black.opacity(0.6), radius: 4, y: 2)
            case .accent:
                shape.fill(.themeAccent).overlay(Rectangle().fill(.themeOnAccent).frame(width: 14, height: 2))
            case .outlined:
                shape.fill(theme.surface.color.color)
                    .overlay(shape.strokeBorder(.themeInk, lineWidth: 1.5))
                    .overlay(Rectangle().fill(.themeInk).frame(width: 12, height: 1.5))
            }
        }
        .background {
            // A printed cap's soft offset shadow, or the theme's hard one.
            if look == .outlined || theme.controls?.shadow == .hard {
                shape.fill(.themeInk.opacity(theme.controls?.shadow == .hard ? 1 : 0.15)).offset(x: 2, y: 2)
            }
        }
    }
}

/// How a theme draws a fader's cap, from its controls.
private enum FaderCap {
    /// Black's: an ink cap with a glowing ink fill.
    case lit
    /// A theme that selects on its accent (Terminal): an accent block with a grip line.
    case accent
    /// A theme with outlined controls (Paper): a cap in the sheet's color, outlined in ink.
    case outlined
}

extension Theme {
    fileprivate var faderCap: FaderCap {
        if selectsOnAccent { return .accent }
        return controls?.style == .outline ? .outlined : .lit
    }

    /// A focused strip marks its name with the selection (Paper's underline, Terminal's block)
    /// rather than lighting up as a whole, as Black's pill does.
    fileprivate var marksName: Bool { (controls?.selection ?? .pill) != .pill }
}

/// Mutes a channel: the speaker, struck through while muted and lit, in red on most sheets and as
/// an accent block where the theme selects on its accent.
private struct MuteKey: View {
    let muted: Bool
    let symbol: String
    let mutedSymbol: String
    let toggle: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius.map { min($0, 6) } ?? 10, style: .continuous)
        let block = theme.selectsOnAccent
        let ink: Color = !muted ? theme.color(.secondary) : block ? theme.color(.onAccent) : .red
        Button(action: toggle) {
            ThemeSymbol(muted ? mutedSymbol : symbol)
                .themeFont(.body, size: 10.5, weight: .semibold)
                .foregroundStyle(ink)
                .frame(width: 26, height: 20)
                .background {
                    if muted && block {
                        shape.fill(.themeAccent)
                    } else if muted && theme.appearance == .light {
                        shape.strokeBorder(.red, lineWidth: 1.2)
                    } else if muted {
                        shape.fill(.red.opacity(0.2))
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// A line down the middle of its frame, to stroke solid, dashed, or dotted.
private struct VLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}

/// Eleven marks down a fader, one every 10%.
private struct Ticks: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            for tick in 0...10 {
                let y = rect.minY + rect.height * CGFloat(tick) / 10
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
    }
}

/// Two fingers or the wheel up and down over a strip turn it up or down, in whole percent. A local
/// monitor sees only scrolls already addressed to this app, so it costs nothing while the pointer is
/// elsewhere; it's installed only while the strip is on screen.
private struct ScrollCatcher: NSViewRepresentable {
    let nudge: (Double) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.nudge = nudge }

    final class CatcherView: NSView {
        var nudge: ((Double) -> Void)?
        private var monitor: Any?
        /// Scrolled but not yet a whole percent, so slow fingers still move the fader.
        private var pending = 0.0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks belong to the strip

        private func handle(_ event: NSEvent) {
            // Up and down only, not a flick's momentum, and only where the strip shows: sideways
            // scrolls the row of strips.
            guard event.window === window, event.momentumPhase.isEmpty,
                abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                visibleRect.contains(convert(event.locationInWindow, from: nil))
            else { return }
            if event.phase.contains(.began) { pending = 0 }
            pending += scrollStep(
                event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                natural: event.isDirectionInvertedFromDevice)
            let whole = (pending * 100).rounded(.towardZero) / 100
            guard whole != 0 else { return }
            pending -= whole
            nudge?(whole)
        }
    }
}

/// How far a scroll moves a fader: up is louder whichever way scrolling goes; a trackpad moves it
/// 1% per 4 points of finger travel, and a mouse wheel 5% a notch.
func scrollStep(_ deltaY: CGFloat, precise: Bool, natural: Bool) -> Double {
    let up = Double(natural ? -deltaY : deltaY)
    return precise ? up / 400 : up * 0.05
}

private struct DeviceRow: View {
    let device: SoundDevice
    let current: Bool
    let selection: Namespace.ID
    let choose: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Button(action: choose) {
            HStack(spacing: 5) {
                ThemeSymbol(device.symbol)
                    .themeFont(.body, size: 10.5, weight: .semibold)
                    .frame(width: 15)
                Text(SoundView.shortName(device.name))
                    .themeFont(.body, size: 11)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if current {
                    ThemeSymbol("checkmark").themeFont(.body, size: 8.5, weight: .bold)
                }
            }
            .foregroundStyle(.themeInk.opacity(current ? 1 : hovering ? 0.85 : 0.6))
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background {
                if current {
                    Color.clear.themePlatter(0.14, in: shape).matchedGeometryEffect(id: "device", in: selection)
                } else if hovering {
                    Color.clear.themePlatter(0.06, in: shape)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(device.name)
        .accessibilityLabel(device.name)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// The Media tab's output panel: where sound plays, to switch as in the Sound tab, beside the Mac's
/// volume and the volume of the app that's playing.
public struct MediaOutputView: View {
    let mixer: Mixer
    /// The app playing, by bundle identifier.
    let appID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Namespace private var selection

    public init(mixer: Mixer, appID: String?) {
        self.mixer = mixer
        self.appID = appID
    }

    public var body: some View {
        let current = mixer.output?.id
        HStack(alignment: .top, spacing: 12) {
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(mixer.outputs) { device in
                        DeviceRow(device: device, current: device.id == current, selection: selection) {
                            mixer.choose(device, for: .output)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .fadingEdges(.vertical, length: 6)
            VStack(spacing: 10) {
                if let output = mixer.output {
                    LevelSlider(
                        symbol: output.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        title: SoundView.shortName(output.name), level: output.isMuted ? 0 : output.level,
                        tint: theme.color(.ink),
                        enabled: output.hasVolume
                    ) { mixer.setDeviceLevel($0, for: .output) }
                }
                if let app = mixer.apps.first(where: { $0.id == appID }) {
                    LevelSlider(
                        image: mixer.icon(for: app), title: app.name,
                        level: mixer.isMuted(app.id) ? 0 : mixer.level(of: app.id),
                        tint: mixer.tint(for: app) ?? theme.color(.ink),
                        enabled: true
                    ) { mixer.setLevel($0, of: app.id) }
                }
            }
            .frame(width: 128)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: current)
        .onAppear { mixer.appeared() }
        .onDisappear { mixer.disappeared() }
    }
}

/// A slim sideways fader with what it controls and its level above it. Drag or click along it.
private struct LevelSlider: View {
    var symbol: String?
    var image: NSImage?
    let title: String
    let level: Double
    let tint: Color
    let enabled: Bool
    let set: (Double) -> Void

    init(
        symbol: String? = nil, image: NSImage? = nil, title: String, level: Double, tint: Color, enabled: Bool,
        set: @escaping (Double) -> Void
    ) {
        self.symbol = symbol
        self.image = image
        self.title = title
        self.level = level
        self.tint = tint
        self.enabled = enabled
        self.set = set
    }

    private var percent: Int { Int((min(max(level, 0), 1) * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let image {
                    Image(nsImage: image).resizable().frame(width: 13, height: 13)
                } else if let symbol {
                    ThemeSymbol(symbol).themeFont(.body, size: 10, weight: .semibold).frame(width: 13)
                }
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(percent)%").monospacedDigit().foregroundStyle(.themeInk.opacity(0.5))
            }
            .themeFont(.body, size: 10.5, weight: .medium)
            GeometryReader { proxy in
                Capsule()
                    .fill(.themeInk.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: max(6, proxy.size.width * min(max(level, 0), 1)))
                    }
                    .contentShape(Capsule())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { drag in
                            set(min(max(drag.location.x / max(proxy.size.width, 1), 0), 1))
                        },
                        isEnabled: enabled)
            }
            .frame(height: 6)
        }
        .opacity(enabled ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(percent)%")
        .accessibilityAdjustableAction { direction in
            set(min(max(level + (direction == .increment ? 0.05 : -0.05), 0), 1))
        }
    }
}

extension Mixer {
    /// For the Sound tab's settings: what it does, and a way back to every app's own volume.
    public var settingsView: some View { MixerSettings(mixer: self) }
}

private struct MixerSettings: View {
    let mixer: Mixer

    var body: some View {
        LabeledContent {
            Button("Reset All") { mixer.resetAll() }
                .disabled(mixer.levels.isEmpty && mixer.muted.isEmpty)
        } label: {
            Text("App volumes")
            Text(
                "Turn each app up, down, or off in the Sound tab. It uses the waveform's system audio permission, "
                    + "and nothing is recorded.")
        }
    }
}

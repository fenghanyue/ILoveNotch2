// SPDX-License-Identifier: MIT
import AVFoundation
import NotchTheme
import SwiftUI

/// The mirror tab: the camera, round in a ring light or full across the tab, or the step it needs
/// first.
struct MirrorView: View {
    let mirror: MirrorFeature

    var body: some View {
        switch mirror.access {
        case .notDetermined:
            FeatureUnavailableView(
                symbol: "web.camera", title: "A mirror in your notch",
                message: "Uses the camera only while this tab is open. Nothing is recorded.",
                action: ("Continue", mirror.requestAccess))  // App Review 5.1.1(iv): not "Allow"
        case .denied:
            FeatureUnavailableView(
                symbol: "video.slash", title: "Camera access is off",
                message: "Allow ILoveNotch in System Settings › Privacy & Security › Camera.",
                action: ("Open Privacy Settings", { NSWorkspace.shared.open(.privacySettings("Privacy_Camera")) }))
        case .granted where mirror.cameraMissing:
            FeatureUnavailableView(
                symbol: "video.slash", title: "No camera", message: "Connect a camera to use the mirror.")
        case .granted:
            MirrorStage(mirror: mirror, loading: !mirror.isRunning) {
                CameraPreview(session: mirror.camera.session)
            }
        }
    }
}

/// The mirror around a picture: the camera's, or a stand-in in the snapshots. Round in the middle
/// of a ring light, with the light's brightness and warmth on the left and the framing guides on the
/// right; or full across the tab, under a slim bar that steps aside while the pointer rests. The
/// ring is real light from the screen, so it lights your face; it eases to a new brightness and
/// never pulses, and nothing here redraws on a timer.
struct MirrorStage<Picture: View>: View {
    let mirror: MirrorFeature
    /// The camera is starting: a small spinner over the picture.
    var loading = false
    @ViewBuilder let picture: Picture

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if mirror.showsFull { full } else { lens }
    }

    private var style: RingStyle { RingStyle(theme) }

    /// Whether the light glows past its edge: on a dark sheet, without Reduce Transparency.
    private var glows: Bool { theme.appearance == .dark && !reduceTransparency }

    private var light: Color { mirror.warmth.light }

    private var percent: Int { Int((mirror.brightness * 100).rounded()) }

    private func eased(_ duration: Double) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }

    // MARK: Round mirror

    /// The ring light in the middle, its brightness and warmth on the left, and the guides, the
    /// full view, and Flip on the right. A shorter notch drops the headings and tightens the rows.
    private var lens: some View {
        GeometryReader { proxy in
            let fit = LensFit(proxy.size)
            HStack(spacing: LensFit.gap) {
                ViewThatFits(in: .vertical) {
                    lightColumn(regular: true)
                    lightColumn(regular: false)
                }
                .frame(width: fit.column, height: proxy.size.height, alignment: .topLeading)
                ring(fit)
                ViewThatFits(in: .vertical) {
                    guideColumn(regular: true)
                    guideColumn(regular: false)
                }
                .frame(width: fit.column, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .background { lensKeys }
    }

    /// The ring, its knob at the brightness, and the round mirror inside. Dragging round the ring
    /// sets the brightness.
    private func ring(_ fit: LensFit) -> some View {
        let scale = fit.scale
        let angle = mirror.brightness * 2 * .pi
        return ZStack {
            ringLight(scale)
            knob(scale)
                .offset(x: 116 * scale * sin(angle), y: -116 * scale * cos(angle))
            roundPicture(scale)
            if style == .blocks {
                Brackets(arm: 22 * scale).stroke(.themeInk, lineWidth: 2).padding(1)
            }
        }
        .frame(width: fit.side, height: fit.side)
        .background {
            if style == .glow, glows { halo(scale) }
        }
        .contentShape(Band(inner: 103 * scale, outer: 131 * scale), eoFill: true)
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { drag in
                let (x, y) = (drag.location.x - fit.side / 2, drag.location.y - fit.side / 2)
                let angle = atan2(x, -y)
                let fraction = (angle < 0 ? angle + 2 * .pi : angle) / (2 * .pi)
                // The first change is where the drag starts: it sets the brightness outright.
                let previous = drag.translation == .zero ? nil : mirror.brightness
                mirror.setBrightness(MirrorFeature.ringBrightness(at: fraction, previous: previous))
            }
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: mirror.brightness)
        .animation(eased(0.2), value: mirror.guides)
    }

    /// The light around the ring, wider and brighter as the ring brightens.
    private func halo(_ scale: CGFloat) -> some View {
        let level = mirror.brightness
        return RadialGradient(
            colors: [light.opacity(0.4), .clear], center: .center, startRadius: 116 * scale,
            endRadius: (140 + 40 * level) * scale
        )
        .frame(width: 360 * scale, height: 360 * scale)
        .opacity(0.25 + 0.75 * level)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The ring in the theme's style: a band that glows brighter, a printed dial inked up to the
    /// brightness, or forty blocks lit up to it.
    @ViewBuilder private func ringLight(_ scale: CGFloat) -> some View {
        let level = mirror.brightness
        let side = 232 * scale
        Group {
            switch style {
            case .glow:
                ZStack {
                    Circle().stroke(light.opacity(0.14), lineWidth: 14 * scale)
                    Circle().stroke(light, lineWidth: 8 * scale)
                        .shadow(color: glows ? light.opacity(0.9) : .clear, radius: (4 + 12 * level) * scale)
                        .opacity(level)
                }
                .frame(width: side, height: side)
            case .printed:
                let marks = { (lit: Bool) in
                    Marks(count: 72, inner: 109.5 * scale, outer: 122.5 * scale, level: level, lit: lit)
                }
                ZStack {
                    Circle().stroke(light.opacity(0.4 + 0.6 * level), lineWidth: 14 * scale)
                        .frame(width: side, height: side)
                    marks(false).stroke(.themeInk.opacity(0.28), lineWidth: 1)
                    marks(true).stroke(.themeInk, lineWidth: 1.6)
                    Circle().stroke(.themeInk, lineWidth: 1.2).frame(width: 216 * scale, height: 216 * scale)
                    Circle().stroke(.themeInk, lineWidth: 1.2).frame(width: 248 * scale, height: 248 * scale)
                }
            case .blocks:
                let marks = { (lit: Bool) in
                    Marks(count: 40, inner: 110 * scale, outer: 123 * scale, level: level, lit: lit)
                }
                ZStack {
                    marks(false).stroke(.themeInk.opacity(0.22), lineWidth: 8 * scale)
                    marks(true).stroke(light, lineWidth: 8 * scale)
                        .shadow(color: glows ? light.opacity(0.7) : .clear, radius: 6 * scale)
                    if theme.appearance == .light {
                        // A pale light on a light sheet takes an edge in the ink.
                        marks(true).stroke(lineWidth: 8 * scale).stroke(.themeInk, lineWidth: 1.5)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The handle at the brightness on the ring: in the ink, or the sheet's color edged in it, square
    /// where the theme's controls are.
    private func knob(_ scale: CGFloat) -> some View {
        let shape = theme.controls?.radius == 0 ? AnyShape(Rectangle()) : AnyShape(Circle())
        let side = max(10, 16 * scale)
        return ZStack {
            if style == .glow {
                shape.fill(.themeInk).shadow(color: glows ? light : .clear, radius: 6)
            } else {
                shape.fill(theme.surface.color.color)
                shape.stroke(.themeInk, lineWidth: style == .blocks ? 2 : 1.5)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The picture, round and flipped like a mirror, with the guides over it; matted like a round
    /// print on a light sheet.
    @ViewBuilder private func roundPicture(_ scale: CGFloat) -> some View {
        let mat = style == .printed ? 5 * scale : 0
        let side = 206 * scale - 2 * mat
        let edge =
            style == .printed
            ? theme.color(.ink) : theme.controls?.lineColor?.color ?? theme.color(.ink).opacity(0.12)
        picture
            .scaleEffect(x: mirror.mirrored ? -1 : 1, y: 1)
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay { guideLines.clipShape(Circle()) }
            .overlay { spinner }
            .padding(mat)
            .background {
                if style == .printed { Circle().fill(theme.surface.color.color) }
            }
            .overlay { Circle().strokeBorder(edge, lineWidth: style == .printed ? 1.2 : 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mirror.mirrored ? "Camera mirror" : "Camera, as others see you")
    }

    /// The guides that are on, fading in and out.
    private var guideLines: some View {
        let ink = style == .printed ? theme.surface.color.color : theme.color(.ink).opacity(style == .glow ? 0.62 : 1)
        let dash: [CGFloat] =
            switch style {
            case .glow: [4, 5]
            case .printed: [2, 4]
            case .blocks: [2, 3]
            }
        return ZStack {
            ForEach(MirrorFeature.Guide.allCases, id: \.self) { guide in
                GuideLine(guide: guide)
                    .stroke(ink, style: StrokeStyle(lineWidth: style == .printed ? 1.2 : 1, dash: dash))
                    .opacity(mirror.guides.contains(guide) ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var spinner: some View {
        if loading { ProgressView().controlSize(.small) }
    }

    // MARK: Light

    /// The ring light: how bright, the slider, and its warmth; at the foot, that it's live.
    private func lightColumn(regular: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if regular { caption("Ring light").padding(.bottom, 3) }
            Text("\(percent)%")
                .themeFont(.display, size: regular ? 28 : 20, weight: .semibold)
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityHidden(true)  // the slider says it
            brightnessSlider.padding(.top, regular ? 6 : 4)
            if regular { caption("Warmth").padding(.top, 10).padding(.bottom, 4) }
            ViewThatFits(in: .horizontal) {
                warmthSegments
                warmthCycle
            }
            .padding(.top, regular ? 0 : 6)
            if regular {
                Text("Drag the ring, or ↑\u{00A0}↓")  // the arrows stay together
                    .themeFont(.body, size: 10)
                    .foregroundStyle(.themeSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 4)
            live(long: regular)
                .foregroundStyle(.themeSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A heading over a group of controls.
    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .tracking(0.6)
            .themeFont(.body, size: 9.5, weight: .semibold)
            .foregroundStyle(.themeSecondary)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }

    /// The brightness, dragged along in 5% steps: a lit bar with a round thumb, a printed rule, or
    /// a block meter, by the theme.
    private var brightnessSlider: some View {
        let thumb: CGSize =
            switch style {
            case .glow: CGSize(width: 16, height: 16)
            case .printed: CGSize(width: 13, height: 13)
            case .blocks: CGSize(width: 5, height: 16)
            }
        return GeometryReader { proxy in
            let track = max(1, proxy.size.width - thumb.width)
            let x = thumb.width / 2 + track * mirror.brightness
            ZStack(alignment: .leading) {
                sliderTrack
                sliderFill.frame(width: x)
                sliderThumb.frame(width: thumb.width, height: thumb.height)
                    .position(x: x, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    mirror.setBrightness((drag.location.x - thumb.width / 2) / track)
                })
        }
        .frame(height: 18)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: mirror.brightness)
        .help("Ring light brightness: drag here or around the ring, or press ↑ ↓")
        .accessibilityElement()
        .accessibilityLabel("Ring light brightness")
        .accessibilityValue("\(percent)%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: mirror.nudgeBrightness(by: 1)
            case .decrement: mirror.nudgeBrightness(by: -1)
            @unknown default: break
            }
        }
    }

    private var trackShape: AnyShape { style == .glow ? AnyShape(Capsule()) : AnyShape(Rectangle()) }

    private var trackHeight: CGFloat {
        switch style {
        case .glow: 6
        case .printed: 2
        case .blocks: 10
        }
    }

    @ViewBuilder private var sliderTrack: some View {
        if style == .blocks {
            trackShape.stroke(theme.controls?.lineColor?.color ?? theme.color(.ink).opacity(0.4), lineWidth: 1)
                .frame(height: trackHeight)
        } else {
            trackShape.fill(.themeInk.opacity(style == .printed ? 0.3 : 0.16)).frame(height: trackHeight)
        }
    }

    /// Up to the thumb: the light itself on a dark sheet, the ink on a light one.
    private var sliderFill: some View {
        trackShape.fill(theme.appearance == .dark ? AnyShapeStyle(light) : AnyShapeStyle(.themeInk))
            .frame(height: trackHeight)
    }

    @ViewBuilder private var sliderThumb: some View {
        switch style {
        case .glow:
            Circle().fill(.themeInk).shadow(color: glows ? light.opacity(0.9) : .clear, radius: 6)
        case .printed:
            Circle().fill(theme.surface.color.color).overlay { Circle().strokeBorder(.themeInk, lineWidth: 1.5) }
        case .blocks:
            Rectangle().fill(.themeInk)
        }
    }

    /// Cool, Neutral, and Warm side by side, where they fit.
    private var warmthSegments: some View {
        let radius = theme.controls?.radius ?? 12
        return HStack(spacing: 2) {
            ForEach(MirrorFeature.Warmth.allCases, id: \.self) { warmth in
                let chosen = mirror.warmth == warmth
                Button {
                    mirror.warmth = warmth
                } label: {
                    Text(warmth.title)
                        .fixedSize()
                        .themeFont(.body, size: 10.5, weight: .semibold)
                        .themeSelectionInk(chosen, unlit: 0.7)
                        .padding(.horizontal, 5)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background {
                            if chosen { SelectionMark(in: RoundedRectangle(cornerRadius: max(0, radius - 2))) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(warmth.title) light (W for the next)")
                .accessibilityLabel("\(warmth.title) light")
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .themePlatter(0.08, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// The warmth as one chip with a swatch of the light, stepping to the next on a click.
    private var warmthCycle: some View {
        Button {
            mirror.warmth = mirror.warmth.next
        } label: {
            HStack(spacing: 6) {
                dotShape.fill(light)
                    .overlay { dotShape.stroke(.themeInk.opacity(0.35), lineWidth: 0.5) }
                    .frame(width: 8, height: 8)
                Text(mirror.warmth.title).fixedSize()
                Spacer(minLength: 0)
                ThemeSymbol("arrow.clockwise")
                    .themeFont(.body, size: 9, weight: .semibold)
                    .foregroundStyle(.themeSecondary)
            }
            .themeFont(.body, size: 11, weight: .semibold)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 24)
            .themePlatter(0.08, in: RoundedRectangle(cornerRadius: theme.controls?.radius ?? 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(mirror.warmth.title) light: click or press W for the next")
        .accessibilityLabel("Ring light warmth")
        .accessibilityValue(mirror.warmth.title)
    }

    /// Round, or square where the theme's controls are.
    private var dotShape: AnyShape { theme.controls?.radius == 0 ? AnyShape(Rectangle()) : AnyShape(Circle()) }

    /// That the camera is on, and that nothing is kept; the dot sits on the first line.
    private func live(long: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            dotShape.fill(Color.green).frame(width: 6, height: 6)  // live: green in every theme
            Text(long ? "Live · nothing is recorded" : "Live")
        }
        .themeFont(.body, size: 10, weight: .medium)
        .accessibilityElement(children: .combine)
    }

    // MARK: Guides

    /// The guides to toggle, and at the foot the full view and Flip.
    private func guideColumn(regular: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if regular { caption("Guides").padding(.bottom, 4) }
            // The keys show on every row or none.
            ViewThatFits(in: .horizontal) {
                guideRows(height: regular ? 24 : 20, keys: true)
                guideRows(height: regular ? 24 : 20, keys: false)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                showFullButton
                flipChip
            }
        }
    }

    private func guideRows(height: CGFloat, keys: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(MirrorFeature.Guide.allCases, id: \.self) { guideRow($0, height: height, key: keys) }
        }
    }

    /// A guide with its box, ticked while it's on, and its key where there's room.
    private func guideRow(_ guide: MirrorFeature.Guide, height: CGFloat, key: Bool) -> some View {
        let on = mirror.guides.contains(guide)
        return Button {
            mirror.toggle(guide)
        } label: {
            HStack(spacing: 7) {
                checkbox(on)
                Text(guide.title).fixedSize()
                Spacer(minLength: 2)
                if key {
                    Text(String(guide.key).uppercased()).fixedSize().foregroundStyle(.themeSecondary)
                }
            }
            .themeFont(.body, size: 11, weight: .medium)
            .foregroundStyle(.themeInk.opacity(on ? 1 : 0.72))
            .padding(.horizontal, 4)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(guide.title) (\(String(guide.key).uppercased()))")
        .accessibilityLabel(guide.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A box, filled with a tick while it's on: in the accent where the theme selects on it, outlined
    /// in the ink in an outlined theme, else filled with the ink.
    private func checkbox(_ on: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius == 0 ? 0 : 3.5, style: .continuous)
        let outlined = theme.controls?.style == .outline && !theme.selectsOnAccent
        let tick: Color =
            theme.selectsOnAccent ? theme.color(.onAccent) : outlined ? theme.color(.ink) : theme.surface.color.color
        return ZStack {
            if on {
                if theme.selectsOnAccent {
                    shape.fill(.themeAccent)
                } else if outlined {
                    shape.strokeBorder(.themeInk, lineWidth: 1.5)
                } else {
                    shape.fill(.themeInk)
                }
                ThemeSymbol("checkmark").themeFont(.body, size: 7.5, weight: .bold).foregroundStyle(tick)
            } else {
                shape.strokeBorder(.themeInk.opacity(0.45), lineWidth: 1.2)
            }
        }
        .frame(width: 13, height: 13)
    }

    /// Flip, F: as a mirror shows you, or as others see you.
    private var flipChip: some View {
        Button {
            mirror.mirrored.toggle()
        } label: {
            HStack(spacing: 5) {
                ThemeSymbol("flip.horizontal")
                Text("Flip")
            }
            .fixedSize()
            .themeFont(.body, size: 11.5, weight: .semibold)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .themePlatter(0.12, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: [])
        .help(mirror.mirrored ? "Flip to see yourself as others do (F)" : "Flip back to a mirror (F)")
        .accessibilityLabel("Flip")
        .accessibilityValue(mirror.mirrored ? "Mirrored" : "As others see you")
    }

    private var showFullButton: some View {
        Button {
            mirror.showsFull = true
        } label: {
            ThemeSymbol("arrow.up.left.and.arrow.down.right")
                .themeFont(.body, size: 11.5, weight: .semibold)
                .frame(width: 28, height: 26)
                .themePlatter(0.12, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show the camera full")
        .accessibilityLabel("Show the camera full")
    }

    /// While the notch has the keyboard: ↑ and ↓ brighten and dim, W steps the warmth, and C, E, and
    /// T toggle the guides.
    private var lensKeys: some View {
        Group {
            Button("Brighter") { mirror.nudgeBrightness(by: 1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Dimmer") { mirror.nudgeBrightness(by: -1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("Next warmth") { mirror.warmth = mirror.warmth.next }
                .keyboardShortcut("w", modifiers: [])
            ForEach(MirrorFeature.Guide.allCases, id: \.self) { guide in
                Button(guide.title) { mirror.toggle(guide) }
                    .keyboardShortcut(KeyEquivalent(guide.key), modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Full view

    /// The camera across the tab, cropped to fill and flipped like a mirror, under a slim bar: a
    /// rounded picture, a print on its mat, or a square one in corner brackets, by the theme. The
    /// fill light lights its rim.
    @ViewBuilder private var full: some View {
        let radius: CGFloat =
            switch style {
            case .glow: theme.controls?.radius ?? 18
            case .printed: 2
            case .blocks: 0
            }
        let frame = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let inset: CGFloat = style == .glow ? 0 : 6
        picture
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(x: (mirror.mirrored ? -1 : 1) * mirror.zoom, y: mirror.zoom)
            .clipShape(RoundedRectangle(cornerRadius: max(0, radius - inset), style: .continuous))
            .overlay { spinner }
            .overlay(alignment: .topLeading) { livePill.padding(8) }
            .overlay {
                HidingBar {
                    ViewThatFits(in: .horizontal) {
                        bar(labels: true)
                        bar(labels: false)
                    }
                    .padding(8)
                }
            }
            .padding(inset)
            .background {
                if style == .printed {
                    // A print: its mat, edged in the ink, on an offset backing.
                    frame.fill(.themeInk.opacity(0.1)).offset(x: 4, y: 4)
                    frame.fill(theme.surface.color.color)
                    frame.strokeBorder(.themeInk.opacity(0.45), lineWidth: 1)
                }
            }
            .overlay {
                if mirror.fillLight {
                    frame.strokeBorder(light, lineWidth: 5)
                        .shadow(color: reduceTransparency ? .clear : light.opacity(0.8), radius: 18)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if style == .blocks {
                    Brackets(arm: 22).stroke(.themeInk, lineWidth: 2).padding(1)
                        .shadow(color: mirror.fillLight && glows ? light : .clear, radius: 5)
                        .allowsHitTesting(false)
                }
            }
            .animation(eased(0.25), value: mirror.zoom)
            .animation(eased(0.3), value: mirror.fillLight)
    }

    private var livePill: some View {
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius ?? 10, style: .continuous)
        return live(long: true)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 20)
            .themePlatter(0.08, in: shape)
            .background(theme.surface.color.color.opacity(0.75), in: shape)
    }

    /// Flip; zoom to 1×, 1.5×, or 2× (1, 2, 3); the fill light (L); and back to the round mirror. A
    /// narrow notch drops the fill light's name.
    private func bar(labels: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius ?? 18, style: .continuous)
        return HStack(spacing: 2) {
            barButton(nil, symbol: "flip.horizontal", label: "Flip", key: "f") { mirror.mirrored.toggle() }
            barRule
            ForEach(Array(MirrorFeature.zooms.enumerated()), id: \.offset) { index, zoom in
                barButton(
                    "\(zoom.formatted())×", label: "Zoom \(zoom.formatted())×", key: Character(String(index + 1)),
                    lit: mirror.zoom == zoom
                ) { mirror.zoom = zoom }
            }
            barRule
            barButton(
                labels ? "Fill light" : nil, symbol: mirror.fillLight ? "sun.max.fill" : "sun.max",
                label: "Fill light", key: "l", lit: mirror.fillLight
            ) { mirror.fillLight.toggle() }
            barRule
            barButton(nil, symbol: "arrow.down.right.and.arrow.up.left", label: "Back to the round mirror", key: nil) {
                mirror.showsFull = false
            }
        }
        .padding(3)
        .themePlatter(0.1, in: shape)
        .background(theme.surface.color.color.opacity(0.8), in: shape)
        .fixedSize()
    }

    private var barRule: some View {
        Rectangle().fill(.themeInk.opacity(0.2)).frame(width: 1, height: 16).padding(.horizontal, 2)
    }

    private func barButton(
        _ title: String?, symbol: String? = nil, label: String, key: Character?, lit: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let mark = RoundedRectangle(cornerRadius: max(0, (theme.controls?.radius ?? 18) - 3), style: .continuous)
        return Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { ThemeSymbol(symbol) }
                if let title { Text(title).monospacedDigit() }
            }
            .fixedSize()
            .themeFont(.body, size: 11.5, weight: .semibold)
            .themeSelectionInk(lit, unlit: 0.85)
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 26)
            .background {
                if lit { SelectionMark(in: mark, strength: 0.18) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key.map { KeyboardShortcut(KeyEquivalent($0), modifiers: []) })
        .help(key.map { "\(label) (\(String($0).uppercased()))" } ?? label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// The full view's bar over the foot of the picture. It fades out 2 s after the pointer last moved
/// over the picture or left it, and back in as soon as it moves there again; it stays while the
/// pointer rests on it, and always with Reduce Motion or VoiceOver. A one-off wait, not a timer.
private struct HidingBar<Bar: View>: View {
    @ViewBuilder let bar: Bar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var resting = false
    @State private var onBar = false
    /// Counts the pointer's moves, each starting the wait over.
    @State private var moves = 0

    var body: some View {
        let shown = !resting || onBar || reduceMotion || voiceOver
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active = phase { resting = false }
                moves += 1
            }
            .overlay(alignment: .bottom) {
                bar
                    .onHover { onBar = $0 }
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: shown)
            }
            .task(id: moves) {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                resting = true
            }
    }
}

/// The round mirror's size in the space the tab has: the mock's ring and its brackets, 262 pt
/// across, scaled to the height but never past it, leaving each column beside it `minColumn`.
private struct LensFit {
    static let gap: CGFloat = 8
    private static let minColumn: CGFloat = 100
    private static let mock: CGFloat = 262

    let side: CGFloat
    let column: CGFloat
    /// The mock's ring is 1.
    var scale: CGFloat { side / Self.mock }

    init(_ size: CGSize) {
        side = max(0, min(size.height, size.width - 2 * (Self.minColumn + Self.gap), Self.mock))
        column = max(0, (size.width - side) / 2 - Self.gap)
    }
}

/// How the ring draws, from the theme's shapes as the timer's dial does: square controls cut it into
/// forty blocks (Terminal), a light sheet prints it as a dial (Paper), and the rest glow (Black).
private enum RingStyle {
    case glow, printed, blocks

    init(_ theme: Theme) {
        if theme.controls?.radius == 0 {
            self = .blocks
        } else {
            self = theme.appearance == .light ? .printed : .glow
        }
    }
}

extension MirrorFeature.Warmth {
    /// The ring's light: the screen's white, cooled or warmed. The light on your face, so the same in
    /// every theme.
    var light: Color {
        switch self {
        case .cool: Color(red: 0.85, green: 0.92, blue: 1)
        case .neutral: Color(red: 1, green: 0.96, blue: 0.9)
        case .warm: Color(red: 1, green: 0.86, blue: 0.71)
        }
    }
}

/// Marks round the ring from `inner` to `outer` out from its center, `count` of them from the top
/// going clockwise: those lit up to `level` (0...1), or the rest. Paper's ticks and Terminal's
/// blocks; they ink or light in turn as the level animates.
private struct Marks: Shape {
    let count: Int
    let inner: CGFloat
    let outer: CGFloat
    var level: Double
    let lit: Bool

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            for index in 0..<count {
                let fraction = (Double(index) + 0.5) / Double(count)
                guard (fraction <= level) == lit else { continue }
                let (x, y) = (sin(fraction * 2 * .pi), -cos(fraction * 2 * .pi))
                path.move(to: CGPoint(x: rect.midX + inner * x, y: rect.midY + inner * y))
                path.addLine(to: CGPoint(x: rect.midX + outer * x, y: rect.midY + outer * y))
            }
        }
    }
}

/// A guide over the round mirror: down the middle, across where the eyes sit (a little above the
/// middle), or the thirds both ways.
private struct GuideLine: Shape {
    let guide: MirrorFeature.Guide

    func path(in rect: CGRect) -> Path {
        // At the mock's 206 pt lens.
        func x(_ value: CGFloat) -> CGFloat { rect.minX + rect.width * value / 206 }
        func y(_ value: CGFloat) -> CGFloat { rect.minY + rect.height * value / 206 }
        return Path { path in
            switch guide {
            case .center:
                path.move(to: CGPoint(x: rect.midX, y: y(14)))
                path.addLine(to: CGPoint(x: rect.midX, y: y(192)))
            case .eyes:
                path.move(to: CGPoint(x: x(28), y: y(86)))
                path.addLine(to: CGPoint(x: x(178), y: y(86)))
            case .thirds:
                for third: CGFloat in [206 / 3, 412 / 3] {
                    path.move(to: CGPoint(x: x(third), y: rect.minY))
                    path.addLine(to: CGPoint(x: x(third), y: rect.maxY))
                    path.move(to: CGPoint(x: rect.minX, y: y(third)))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y(third)))
                }
            }
        }
    }
}

/// Corner brackets `arm` long at the frame's corners, like a viewfinder's.
private struct Brackets: Shape {
    let arm: CGFloat

    func path(in rect: CGRect) -> Path {
        // Each corner, and which way its arms run.
        let corners: [(x: CGFloat, y: CGFloat, across: CGFloat, down: CGFloat)] = [
            (rect.minX, rect.minY, 1, 1), (rect.maxX, rect.minY, -1, 1), (rect.minX, rect.maxY, 1, -1),
            (rect.maxX, rect.maxY, -1, -1),
        ]
        return Path { path in
            for corner in corners {
                path.move(to: CGPoint(x: corner.x + corner.across * arm, y: corner.y))
                path.addLine(to: CGPoint(x: corner.x, y: corner.y))
                path.addLine(to: CGPoint(x: corner.x, y: corner.y + corner.down * arm))
            }
        }
    }
}

/// The ring's band, between two circles round the center: where a drag sets the brightness.
private struct Band: Shape {
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for radius in [outer, inner] {
            let center = CGRect(x: rect.midX, y: rect.midY, width: 0, height: 0)
            path.addEllipse(in: center.insetBy(dx: -radius, dy: -radius))
        }
        return path
    }
}

/// The capture session's live picture, filling its frame.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer = preview
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

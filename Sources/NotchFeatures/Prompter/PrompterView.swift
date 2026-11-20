// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI

/// The prompter tab: the script to edit, or to read with its controls under it.
struct PrompterView: View {
    @Bindable var prompter: PrompterFeature

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            if prompter.isReading { reading } else { editor }
            if let problem = prompter.problem { problemRow(problem) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Editing

    private var editor: some View {
        VStack(spacing: 8) {
            TextEditor(text: $prompter.script)
                .themeFont(.body, .callout)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Script")
                .padding(6)
                .background(.themeInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if prompter.script.isEmpty {
                        Text("Paste or type your script, or import a text file, Markdown, or a deck's speaker notes.")
                            .themeFont(.body, .callout)
                            .foregroundStyle(.themeInk.opacity(0.4))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            HStack(spacing: 4) {
                ForEach(PrompterFeature.Mode.allCases, id: \.self, content: modeButton)
                Spacer(minLength: 4)
                control("Import\u{2026}", prompter.importScript)
                control("Start", prompter.start)
                    .disabled(prompter.script.allSatisfy(\.isWhitespace))
            }
        }
    }

    private func modeButton(_ mode: PrompterFeature.Mode) -> some View {
        Button(mode.title) { prompter.mode = mode }
            .buttonStyle(.plain)
            .themeFont(.body, .caption, weight: .semibold)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(prompter.mode == mode ? theme.color(.ink).opacity(0.16) : .clear, in: Capsule())
            .help(Self.explanation(mode))
            .accessibilityHint(Self.explanation(mode))
            .accessibilityAddTraits(prompter.mode == mode ? .isSelected : [])
    }

    private static func explanation(_ mode: PrompterFeature.Mode) -> String {
        switch mode {
        case .voice: "Follows the words you say and waits when you pause. Recognized on this Mac."
        case .scroll: "Moves on at a steady pace. No microphone."
        case .words: "Moves on at a steady pace while it hears you speak."
        }
    }

    // MARK: Reading

    private var reading: some View {
        VStack(spacing: 6) {
            ScriptText(
                script: prompter.script, ranges: prompter.wordRanges, current: prompter.current,
                style: scriptStyle
            )
            .scaleEffect(x: prompter.mirrored ? -1 : 1, y: 1)
            .fadingEdges(length: ScriptScrollView.fade)
            .accessibilityLabel("Script")
            controls
        }
    }

    /// The script in the theme's body face and ink, the current word on its highlight, or a lighter
    /// ink without one.
    private var scriptStyle: ScriptStyle {
        let ink = NSColor(theme.color(.ink))
        return ScriptStyle(
            font: theme.nsFont(.body, size: prompter.textSize, weight: .semibold), ink: ink,
            highlight: theme.colors.highlight.map { NSColor($0.color) } ?? ink.withAlphaComponent(0.2),
            current: theme.colors.onHighlight.map { NSColor($0.color) } ?? ink)
    }

    private var controls: some View {
        HStack(spacing: 2) {
            icon(prompter.isRunning ? "pause.fill" : "play.fill", prompter.isRunning ? "Pause" : "Read") {
                prompter.toggle()
            }
            .disabled(prompter.isFinished)
            .help(prompter.isRunning ? "Pause (Control-Option-P)" : "Read (Control-Option-P)")
            icon("backward.end.fill", "Back to the start", action: prompter.restart)
            modeMenu
            if prompter.mode != .voice { speedMenu }
            icon("textformat.size.smaller", "Smaller text") { prompter.textSize -= 2 }
                .disabled(prompter.textSize <= PrompterFeature.textSizes.lowerBound)
            icon("textformat.size.larger", "Larger text") { prompter.textSize += 2 }
                .disabled(prompter.textSize >= PrompterFeature.textSizes.upperBound)
            icon("flip.horizontal", prompter.mirrored ? "Unmirror" : "Mirror", lit: prompter.mirrored) {
                prompter.mirrored.toggle()
            }
            Spacer(minLength: 4)
            time
            icon("pencil", "Edit the script", action: prompter.edit)
        }
        .buttonStyle(.plain)
    }

    private var modeMenu: some View {
        Menu {
            Picker("Follow", selection: $prompter.mode) {
                ForEach(PrompterFeature.Mode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            ThemeSymbol(prompter.mode.symbol).frame(width: 24, height: 22)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(prompter.mode.title): \(Self.explanation(prompter.mode))")
        .accessibilityLabel("Mode, \(prompter.mode.title)")
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: $prompter.speed) {
                ForEach(PrompterFeature.speeds, id: \.self) { Text("\($0.formatted())×").tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Text("\(prompter.speed.formatted())×").themeFont(.body, .caption, weight: .semibold).monospacedDigit()
                .frame(minWidth: 30, minHeight: 22)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Speed")
        .accessibilityLabel("Speed, \(prompter.speed.formatted()) times")
    }

    /// Time read and time left; it ticks once a second, and only while the script moves.
    private var time: some View {
        TimelineView(.periodic(from: .now, by: prompter.isRunning ? 1 : 3600)) { context in
            let elapsed = formatTime(prompter.stopwatch.elapsed(at: context.date), roundingUp: false)
            let left = formatTime(prompter.remaining(at: context.date))
            Text("\(elapsed) · \(left) left")
                .themeFont(.body, .caption, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(.themeInk.opacity(0.7))
                .lineLimit(1)
                .accessibilityLabel("\(elapsed) read, about \(left) left")
        }
    }

    private func icon(_ symbol: String, _ label: String, lit: Bool = false, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            ThemeSymbol(symbol)
                .themeFont(.body, size: 12, weight: .semibold)
                .frame(width: 24, height: 22)
                .background(lit ? theme.color(.ink).opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .help(label)
        .accessibilityLabel(label)
    }

    private func control(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .themeFont(.body, .callout, weight: .semibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.themeInk.opacity(0.14), in: Capsule())
    }

    // MARK: Problems

    @ViewBuilder private func problemRow(_ problem: PrompterFeature.Problem) -> some View {
        switch problem {
        case .microphone:
            banner(
                "Microphone access is off. Allow ILoveNotch in Privacy & Security, or use Scroll.",
                fix: ("Open Settings", { NSWorkspace.shared.open(.privacySettings("Privacy_Microphone")) }))
        case .speechRecognition:
            banner(
                "Speech Recognition is off. Allow ILoveNotch in Privacy & Security, or use Scroll or Words.",
                fix: ("Open Settings", { NSWorkspace.shared.open(.privacySettings("Privacy_SpeechRecognition")) }))
        case .message(let message):
            banner(message, fix: nil)
        }
    }

    private func banner(_ message: String, fix: (label: String, perform: () -> Void)?) -> some View {
        HStack(spacing: 8) {
            ThemeSymbol("exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if let fix { control(fix.label, fix.perform).themeFont(.body, .caption, weight: .semibold) }
        }
        .themeFont(.body, .caption)
        .accessibilityElement(children: .combine)
    }
}

/// How the script is drawn: its face, its ink (read words dimmed), and what marks the next word,
/// in `current`.
private struct ScriptStyle: Equatable {
    var font: NSFont
    var ink: NSColor
    var highlight: NSColor
    var current: NSColor
}

/// The script as it's read: the words read so far dimmed, the next one lit, and the lines to come
/// under it. AppKit lays the text out once; moving on recolors two ranges and scrolls by a line.
private struct ScriptText: NSViewRepresentable {
    let script: String
    let ranges: [NSRange]
    let current: Int
    let style: ScriptStyle

    func makeNSView(context: Context) -> ScriptScrollView { ScriptScrollView() }

    func updateNSView(_ view: ScriptScrollView, context: Context) {
        view.show(script, style: style)
        view.follow(current < ranges.count ? ranges[current] : nil)
    }
}

private final class ScriptScrollView: NSScrollView {
    private let text = NSTextView(usingTextLayoutManager: false)  // TextKit 1, for its temporary colors
    private var script = ""
    private var style: ScriptStyle?
    /// The next word to read; nil once the script is done.
    private var current: NSRange?
    /// The text was replaced, so its words need coloring again.
    private var uncolored = true
    private var lineSpacing: CGFloat { (style?.font.pointSize ?? 0) * 0.25 }

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = false
        automaticallyAdjustsContentInsets = false
        // The document first: a text view that sizes itself before it's in the (flipped) clip view
        // grows upward, and its first line would sit above the top for good.
        documentView = text
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 0, height: Self.fade)  // the first line clear of the fade
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true
        text.autoresizingMask = .width
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ script: String, style: ScriptStyle) {
        guard script != self.script || style != self.style else { return }
        (self.script, self.style) = (script, style)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        text.textStorage?.setAttributedString(
            NSAttributedString(
                string: script,
                attributes: [
                    .font: style.font, .foregroundColor: style.ink.withAlphaComponent(0.9),
                    .paragraphStyle: paragraph,
                ]))
        uncolored = true
    }

    func follow(_ next: NSRange?) {
        guard next != current || uncolored, let style, let layout = text.layoutManager else { return }
        (current, uncolored) = (next, false)
        let all = NSRange(location: 0, length: (script as NSString).length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        let read = NSRange(location: 0, length: next?.location ?? all.length)
        layout.addTemporaryAttribute(
            .foregroundColor, value: style.ink.withAlphaComponent(0.35), forCharacterRange: read)
        if let next {
            layout.addTemporaryAttribute(.foregroundColor, value: style.current, forCharacterRange: next)
            layout.addTemporaryAttribute(.backgroundColor, value: style.highlight, forCharacterRange: next)
        }
        scrollToCurrent(animated: true)
    }

    /// How far the script fades out at its top and bottom edges.
    static let fade: CGFloat = 8

    /// A new size rewraps the lines, so the current one moves.
    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        scrollToCurrent(animated: false)
    }

    /// Keeps the current word's line second from the top, under one line already read.
    private func scrollToCurrent(animated: Bool) {
        guard !script.isEmpty, let style, let layout = text.layoutManager, let container = text.textContainer
        else { return }
        layout.ensureLayout(for: container)
        let height = layout.usedRect(for: container).height + 2 * Self.fade
        let line: CGFloat
        if let current {
            let glyphs = layout.glyphRange(forCharacterRange: current, actualCharacterRange: nil)
            line = layout.boundingRect(forGlyphRange: glyphs, in: container).minY + text.textContainerOrigin.y
        } else {
            line = height  // done: the last lines
        }
        let above = layout.defaultLineHeight(for: style.font) + lineSpacing
        let top = max(0, min(line - above, height - contentView.bounds.height))
        guard abs(top - contentView.bounds.origin.y) > 0.5 else { return }
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: top))
            }
        } else {
            contentView.setBoundsOrigin(NSPoint(x: 0, y: top))
        }
        reflectScrolledClipView(contentView)
    }
}

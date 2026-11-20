// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI
import Testing

@testable import NotchFeatures

/// The ring light's settings, and the tab drawn per theme. (SystemTests has the camera's lifecycle.)
@MainActor
struct MirrorRingTests {
    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "Mirror-\(UUID())")! }

    @Test func brightnessMovesInFivePercentStepsBetweenOffAndFull() {
        #expect(MirrorFeature.stepped(0.72) == 0.7)
        #expect(MirrorFeature.stepped(0.73) == 0.75)
        #expect(MirrorFeature.stepped(-0.2) == 0)
        #expect(MirrorFeature.stepped(1.4) == 1)
        #expect(MirrorFeature.stepped(.nan) == 0)
        let mirror = MirrorFeature(defaults: freshDefaults())
        mirror.setBrightness(0.95)
        mirror.nudgeBrightness(by: 1)
        mirror.nudgeBrightness(by: 1)
        #expect(mirror.brightness == 1)
        mirror.setBrightness(0.05)
        mirror.nudgeBrightness(by: -1)
        mirror.nudgeBrightness(by: -1)
        #expect(mirror.brightness == 0)
    }

    @Test func draggingRoundTheRingHoldsAtTheTop() {
        #expect(MirrorFeature.ringBrightness(at: 0.26, previous: nil) == 0.25)
        #expect(MirrorFeature.ringBrightness(at: 0.97, previous: nil) == 0.95, "a fresh drag sets it outright")
        #expect(MirrorFeature.ringBrightness(at: 0.03, previous: 0.95) == 1, "past the top from full stays full")
        #expect(MirrorFeature.ringBrightness(at: 0.97, previous: 0.05) == 0, "back past the top from off stays off")
        #expect(MirrorFeature.ringBrightness(at: 0.6, previous: 0.55) == 0.6)
    }

    @Test func everySettingIsRemembered() {
        let defaults = freshDefaults()
        let mirror = MirrorFeature(defaults: defaults)
        #expect(mirror.brightness == 0.7 && mirror.warmth == .warm && mirror.guides == [.center, .eyes])
        #expect(mirror.mirrored && !mirror.showsFull && !mirror.fillLight && mirror.zoom == 1)
        mirror.setBrightness(0.42)
        mirror.warmth = mirror.warmth.next
        mirror.toggle(.center)
        mirror.toggle(.thirds)
        mirror.mirrored = false
        mirror.showsFull = true
        mirror.fillLight = true
        mirror.zoom = 1.5
        let again = MirrorFeature(defaults: defaults)
        #expect(again.brightness == 0.4 && again.warmth == .cool && again.guides == [.eyes, .thirds])
        #expect(!again.mirrored && again.showsFull && again.fillLight && again.zoom == 1.5)
    }

    /// The round mirror and the full view, with a gradient standing in for the camera, at the default
    /// tab size and the smallest, in `AUDIT_THEME` (Black without it). With SNAPSHOT_DIR set, the PNGs
    /// go there as mirror-lens, mirror-full, and each with -smallest.
    @Test func drawsTheLensAndTheFullView() throws {
        let theme = Themes.theme(ProcessInfo.processInfo.environment["AUDIT_THEME"] ?? "black")
        let mirror = MirrorFeature(defaults: freshDefaults())
        let sizes = [("", CGSize(width: 390, height: 190)), ("-smallest", CGSize(width: 350, height: 102))]
        let dusk = [Color(red: 0.24, green: 0.21, blue: 0.32), Color(red: 0.77, green: 0.55, blue: 0.42)]
        for full in [false, true] {
            mirror.showsFull = full
            mirror.fillLight = full
            for (suffix, size) in sizes {
                let stage = MirrorStage(mirror: mirror) {
                    LinearGradient(colors: dusk, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                try render(stage, name: "mirror-\(full ? "full" : "lens")\(suffix)", size: size, theme: theme)
            }
        }
    }

    /// The tab as FeatureSnapshotTests draws one: in the content area, on the theme's sheet.
    private func inNotch(_ view: some View, size: CGSize, theme: Theme) -> some View {
        view
            .frame(width: size.width, height: size.height)
            .padding(16)
            .background(theme.surface.color.color)
            .foregroundStyle(.themeInk)
            .environment(\.colorScheme, theme.appearance.colorScheme)
            .environment(\.theme, theme)
    }

    private func render(_ view: some View, name: String, size: CGSize, theme: Theme) throws {
        let host = NSHostingView(rootView: inNotch(view, size: size, theme: theme))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: size.width + 32, height: size.height + 32),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(filePath: directory).appending(path: "\(name).png"))
        }
    }
}

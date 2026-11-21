// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchTheme
import SwiftUI
import Testing

@testable import NotchMixer

/// Where the shots go; nil skips them.
private let shotsDirectory = ProcessInfo.processInfo.environment["STORE_SHOTS_DIR"]

/// The GitHub build's Sound tab for the website's screenshots: Apple's own apps on their faders,
/// one muted, and the outputs beside them; drawn as NotchFeaturesTests' StoreTabShots draws the App
/// Store edition's tabs (which explains the folder and the order to run them in).
@MainActor
@Suite(.enabled(if: shotsDirectory != nil))
struct StoreTabShots {
    private static let notch = CGSize(width: 600, height: 360)

    @Test func sound() async throws {
        let mixer = Mixer(defaults: UserDefaults(suiteName: "StoreTabShots-\(UUID())")!, live: false)
        let apps = [
            ("com.apple.Music", "Music", "/System/Applications/Music.app", true),
            ("com.apple.Safari", "Safari", "/Applications/Safari.app", true),
            ("com.apple.FaceTime", "FaceTime", "/System/Applications/FaceTime.app", true),
            ("com.apple.podcasts", "Podcasts", "/System/Applications/Podcasts.app", false),
            ("com.apple.MobileSMS", "Messages", "/System/Applications/Messages.app", false),
        ].map { id, name, path, playing in
            MixerApp(id: id, name: name, url: URL(filePath: path), isPlaying: playing)
        }
        mixer.setLevel(0.72, of: "com.apple.Music")
        mixer.setLevel(0.45, of: "com.apple.Safari")
        mixer.setLevel(0.9, of: "com.apple.FaceTime")
        mixer.setLevel(0.6, of: "com.apple.podcasts")
        mixer.setLevel(0.5, of: "com.apple.MobileSMS")
        mixer.toggleMute("com.apple.MobileSMS")
        let outputs = [
            SoundDevice(id: 72, name: "MacBook Pro Speakers", symbol: "speaker.wave.2.fill", connection: "Built-in"),
            SoundDevice(id: 80, name: "AirPods Pro", symbol: "airpodspro", connection: "Bluetooth"),
            SoundDevice(id: 85, name: "Living Room", symbol: "airplayaudio", connection: "AirPlay"),
            SoundDevice(id: 91, name: "Studio Display", symbol: "display", connection: "Thunderbolt"),
        ]
        let airPods = DeviceLevel(
            id: 80, name: "AirPods Pro", level: 0.64, isMuted: false, hasVolume: true, symbol: "airpodspro")
        mixer.preview(apps: apps, output: airPods, outputs: outputs)
        try await Self.draw(SoundView(mixer: mixer), shot: "sound", tab: .sound, theme: "hifi")
    }

    /// Draws `view` as the open notch lays out a tab in `theme`, on nothing, as NotchFeaturesTests'
    /// StoreTabShots.draw does.
    private static func draw(
        _ view: some View, shot: String, tab: FeatureID, theme id: String, wait: Duration = .seconds(1)
    ) async throws {
        guard let directory = shotsDirectory else { return }
        let id = ProcessInfo.processInfo.environment["STORE_SHOTS_THEME"] ?? id  // as NotchFeaturesTests' draw
        let theme = Themes.theme(id)
        let side = theme.radii.notchTop + 22
        let top: CGFloat = 32 + 10 + 26 + 8  // the camera housing, the gap, the tab row, and the gap under it
        let room = CGSize(width: notch.width - 2 * side, height: notch.height - top - 22)
        let root = view.frame(width: room.width, height: room.height)
            .padding(EdgeInsets(top: top, leading: side, bottom: 22, trailing: side))
            .foregroundStyle(.themeInk)
            .environment(\.colorScheme, theme.appearance.colorScheme)
            .environment(\.theme, theme)
            .transaction {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: notch), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: wait)
        runLoop(for: 0.3)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let tabs = URL(filePath: directory).appending(path: "tabs")
        try FileManager.default.createDirectory(at: tabs, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: tabs.appending(path: "\(shot)~\(tab.rawValue)~\(id).png"))
    }

    private static func runLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: .now + seconds)
    }
}

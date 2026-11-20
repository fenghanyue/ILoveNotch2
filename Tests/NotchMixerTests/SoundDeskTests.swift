// SPDX-License-Identifier: MIT
import AppKit
import CoreAudio
import NotchTheme
import SwiftUI
import Testing

@testable import NotchMixer

/// The Sound tab's desk in a theme, at the default and the smallest open size: `AUDIT_THEME=paper`
/// draws it in Paper instead of Black, and with SNAPSHOT_DIR set it writes PNGs there.
@MainActor
struct SoundDeskTests {
    private static let sizes = [("", CGSize(width: 428, height: 200)), ("-smallest", CGSize(width: 350, height: 102))]

    private static let outputs = [
        SoundDevice(id: 72, name: "MacBook Pro Speakers", symbol: "speaker.wave.2.fill", connection: "Built-in"),
        SoundDevice(id: 80, name: "AirPods Pro", symbol: "airpodspro", connection: "Bluetooth"),
        SoundDevice(id: 85, name: "Living Room", symbol: "airplayaudio", connection: "AirPlay"),
        SoundDevice(id: 91, name: "LG HDR 4K", symbol: "tv", connection: "HDMI"),
    ]

    @Test func theDeskInATheme() throws {
        let theme = Themes.theme(ProcessInfo.processInfo.environment["AUDIT_THEME"] ?? "black")
        for (suffix, size) in Self.sizes {
            try render(SoundView(mixer: sampleMixer()), name: "sound-desk" + suffix, size: size, theme: theme)
            let quiet = Mixer(defaults: UserDefaults(suiteName: "SoundDesk-\(UUID())")!, live: false)
            let muted = DeviceLevel(
                id: 80, name: "AirPods Pro", level: 0.3, isMuted: true, hasVolume: true, symbol: "airpodspro")
            quiet.preview(apps: [], output: muted, outputs: Self.outputs)
            try render(SoundView(mixer: quiet), name: "sound-desk-empty" + suffix, size: size, theme: theme)
        }
    }

    @Test func scrollingUpIsLouderWhicheverWayScrollingGoes() {
        #expect(scrollStep(-40, precise: true, natural: true) == 0.1, "fingers up, with natural scrolling")
        #expect(scrollStep(40, precise: true, natural: false) == 0.1, "fingers up, without")
        #expect(scrollStep(-1, precise: false, natural: false) == -0.05, "a wheel's notch down")
    }

    @Test func devicesSayHowTheyConnect() {
        #expect(Mixer.connection(transport: kAudioDeviceTransportTypeBuiltIn) == "Built-in")
        #expect(Mixer.connection(transport: kAudioDeviceTransportTypeBluetoothLE) == "Bluetooth")
        #expect(Mixer.connection(transport: kAudioDeviceTransportTypeAirPlay) == "AirPlay")
        #expect(Mixer.connection(transport: kAudioDeviceTransportTypeUnknown) == nil)
    }

    private func sampleMixer() -> Mixer {
        let mixer = Mixer(defaults: UserDefaults(suiteName: "SoundDesk-\(UUID())")!, live: false)
        let apps = [
            ("com.spotify.client", "Spotify", "/Applications/Spotify.app", true),
            ("com.apple.Safari", "Safari", "/Applications/Safari.app", true),
            ("com.apple.FaceTime", "FaceTime", "/System/Applications/FaceTime.app", true),
            ("com.apple.MobileSMS", "Messages", "/System/Applications/Messages.app", false),
            ("com.apple.Music", "Music", "/System/Applications/Music.app", false),
        ].map { id, name, path, playing in
            MixerApp(id: id, name: name, url: URL(filePath: path), isPlaying: playing)
        }
        mixer.setLevel(0.8, of: "com.spotify.client")
        mixer.setLevel(0.55, of: "com.apple.Safari")
        mixer.setLevel(0.65, of: "com.apple.MobileSMS")
        mixer.toggleMute("com.apple.MobileSMS")
        mixer.setLevel(0.4, of: "com.apple.Music")
        let airPods = DeviceLevel(
            id: 80, name: "AirPods Pro", level: 0.64, isMuted: false, hasVolume: true, symbol: "airpodspro")
        mixer.preview(apps: apps, output: airPods, outputs: Self.outputs)
        return mixer
    }

    /// Draws the view as the notch shows a tab in `theme`, once what rises into place on appearing
    /// has (without animation, so at once).
    private func render(_ view: some View, name: String, size: CGSize, theme: Theme) throws {
        let framed = view.frame(width: size.width, height: size.height)
            .padding(16)
            .background(theme.surface.color.color)
            .foregroundStyle(.themeInk)
            .environment(\.colorScheme, theme.appearance.colorScheme)
            .environment(\.theme, theme)
            .transaction { $0.animation = nil }
        let host = NSHostingView(rootView: framed)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: size.width + 32, height: size.height + 32), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now + 0.1)
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

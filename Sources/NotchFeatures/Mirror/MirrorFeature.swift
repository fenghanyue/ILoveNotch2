// SPDX-License-Identifier: MIT
import AVFoundation
import NotchCore
import Observation
import SwiftUI

/// Camera permission, as the mirror needs it.
public enum CameraAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case granted

    init() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: self = .granted
        case .notDetermined: self = .notDetermined
        default: self = .denied  // denied or restricted
        }
    }
}

/// A mirror from the front camera: round, inside a ring light you can dim and warm, with guides to
/// frame your face; or full across the tab. The camera runs only while this tab is on screen and
/// access is granted, and stops the moment the notch closes or switches tabs; nothing is recorded.
/// The camera is asked for only when the user taps Continue. Every setting is remembered.
@MainActor
@Observable
public final class MirrorFeature: NotchFeature {
    public let id = FeatureID.mirror
    public var phase: FeaturePhase = .stopped {
        didSet { update() }
    }
    public private(set) var access = CameraAccess()
    /// Whether frames are flowing; false before the camera starts and after it stops.
    public private(set) var isRunning = false
    /// No camera could be opened, for example on a Mac mini with none attached.
    public private(set) var cameraMissing = false

    /// The ring light's brightness, 0...1 in 5% steps (`setBrightness`).
    public private(set) var brightness: Double {
        didSet { defaults.set(brightness, forKey: Key.brightness) }
    }
    public var warmth: Warmth {
        didSet { defaults.set(warmth.rawValue, forKey: Key.warmth) }
    }
    /// The lines drawn over the round mirror.
    public var guides: Set<Guide> {
        didSet { defaults.set(guides.map(\.rawValue).sorted(), forKey: Key.guides) }
    }
    /// Flipped left to right, as a mirror shows you; off, as others see you.
    public var mirrored: Bool {
        didSet { defaults.set(mirrored, forKey: Key.mirrored) }
    }
    /// The camera across the whole tab, instead of round inside the ring.
    public var showsFull: Bool {
        didSet { defaults.set(showsFull, forKey: Key.showsFull) }
    }
    /// The full view's rim glows in the ring's light.
    public var fillLight: Bool {
        didSet { defaults.set(fillLight, forKey: Key.fillLight) }
    }
    /// The full view's zoom from the center, one of `zooms`.
    public var zoom: Double {
        didSet { defaults.set(zoom, forKey: Key.zoom) }
    }

    public static let zooms: [Double] = [1, 1.5, 2]

    /// The ring light's color: the screen's white, cooled or warmed.
    public enum Warmth: String, CaseIterable, Sendable {
        case cool, neutral, warm

        public var title: String { rawValue.capitalized }

        /// The one after it, round again after Warm.
        public var next: Warmth {
            switch self {
            case .cool: .neutral
            case .neutral: .warm
            case .warm: .cool
            }
        }
    }

    /// A line over the round mirror, to center your face and level your eyes.
    public enum Guide: String, CaseIterable, Sendable {
        case center, eyes, thirds

        public var title: String {
            switch self {
            case .center: "Center line"
            case .eyes: "Eye line"
            case .thirds: "Thirds"
            }
        }

        /// The key that toggles it while the notch has the keyboard.
        public var key: Character {
            switch self {
            case .center: "c"
            case .eyes: "e"
            case .thirds: "t"
            }
        }
    }

    @ObservationIgnored let camera = CameraSession()
    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let brightness = "mirror.brightness"
        static let warmth = "mirror.warmth"
        static let guides = "mirror.guides"
        static let mirrored = "mirror.mirrored"
        static let showsFull = "mirror.showsFull"
        static let fillLight = "mirror.fillLight"
        static let zoom = "mirror.zoom"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        brightness = Self.stepped(defaults.object(forKey: Key.brightness) as? Double ?? 0.7)
        warmth = defaults.string(forKey: Key.warmth).flatMap(Warmth.init(rawValue:)) ?? .warm
        let guides = defaults.stringArray(forKey: Key.guides)?.compactMap(Guide.init(rawValue:))
        self.guides = guides.map(Set.init) ?? [.center, .eyes]
        mirrored = defaults.object(forKey: Key.mirrored) as? Bool ?? true
        showsFull = defaults.bool(forKey: Key.showsFull)
        fillLight = defaults.bool(forKey: Key.fillLight)
        let zoom = defaults.double(forKey: Key.zoom)
        self.zoom = Self.zooms.contains(zoom) ? zoom : 1
    }

    public var view: some View { MirrorView(mirror: self) }

    /// The brightness at the nearest 5% step to `value`, held between off and full.
    public func setBrightness(_ value: Double) {
        brightness = Self.stepped(value)
    }

    /// `steps` of 5% brighter, or dimmer when negative, as the arrow keys and VoiceOver change it.
    public func nudgeBrightness(by steps: Int) {
        setBrightness(brightness + Double(steps) / 20)
    }

    public func toggle(_ guide: Guide) {
        guides.formSymmetricDifference([guide])
    }

    /// `value` at the nearest 5% step, between 0 and 1. Counted in twentieths, so 70% is exactly 0.7.
    nonisolated static func stepped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max((value * 20).rounded(), 0), 20) / 20
    }

    /// The brightness a drag around the ring sets, `fraction` of the way round from the top going
    /// clockwise. `previous` is the brightness mid-drag (nil where the drag starts): crossing the top
    /// then holds at full or off instead of jumping to the other end.
    nonisolated static func ringBrightness(at fraction: Double, previous: Double?) -> Double {
        let level = stepped(fraction)
        guard let previous else { return level }
        if previous >= 0.75, level < 0.25 { return 1 }
        if previous <= 0.25, level > 0.75 { return 0 }
        return level
    }

    /// The camera runs only while its picture can be seen.
    nonisolated static func runsCamera(phase: FeaturePhase, access: CameraAccess) -> Bool {
        phase == .foreground && access == .granted
    }

    public func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    private func update() {
        access = CameraAccess()
        let run = Self.runsCamera(phase: phase, access: access)
        camera.run(run) { [weak self] running, missing in
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = running
                self.cameraMissing = missing
                Log.features.info("Mirror camera \(running ? "running" : "stopped", privacy: .public)")
            }
        }
    }
}

/// The capture session, confined to its own queue because starting and stopping it blocks for a
/// moment. Configured on first use with the built-in camera, or else the first one found.
final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cafe.opennotch.mirror", qos: .userInitiated)
    // Only touched on `queue`.
    private var configured = false

    /// Starts or stops the camera, then reports whether it runs and whether no camera was found.
    func run(_ running: Bool, completion: @escaping @Sendable (_ running: Bool, _ missing: Bool) -> Void) {
        queue.async { [self] in
            var missing = false
            if running {
                if !configured {
                    configured = configure()
                    missing = !configured
                }
                if configured, !session.isRunning { session.startRunning() }
            } else if session.isRunning {
                session.stopRunning()
            }
            completion(session.isRunning, missing)
        }
    }

    private func configure() -> Bool {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified)
        guard
            let device = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
                ?? discovery.devices.first,
            let input = try? AVCaptureDeviceInput(device: device)
        else { return false }
        session.beginConfiguration()
        // The mirror is a few hundred points wide: a VGA feed is plenty and keeps the camera cheap.
        session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .medium
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        return !session.inputs.isEmpty
    }
}

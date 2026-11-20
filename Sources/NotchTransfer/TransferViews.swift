// SPDX-License-Identifier: MIT
import AppKit
import CoreImage.CIFilterBuiltins
import NotchFeatures
import NotchTheme
import SwiftUI

extension TransferFeature {
    /// The Shelf tab, with a phone's request, its transfer, or the text it sent as a wide tile at
    /// the head of the shelf's grid while there is one.
    public func shelfView(_ shelf: AnyView) -> some View { TransferShelf(transfer: self, shelf: shelf) }

    /// Receiving from Android, for the shelf's bar.
    public var receiveControl: some View { ReceiveControl(transfer: self) }

    /// Settings › Shelf: receiving from Android.
    public var settingsView: some View { TransferSettings(transfer: self) }
}

private struct TransferShelf: View {
    let transfer: TransferFeature
    let shelf: AnyView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        shelf
            .environment(\.shelfIncoming, tile)
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: transfer.incoming?.id)
    }

    /// The phone's tile, once it has said what it's sending.
    private var tile: AnyView? {
        guard let incoming = transfer.incoming, incoming.offer != nil else { return nil }
        return AnyView(IncomingTile(transfer: transfer, incoming: incoming))
    }
}

// MARK: - In the notch

/// A phone asking to send, then its progress, or the text it sent, as a wide tile in the shelf's
/// grid: the phone and what it's sending over what to do, or, a row of the smallest notch tall,
/// all in one line. Without styled controls (Black) it glows in the accent, the one lit tile.
private struct IncomingTile: View {
    let transfer: TransferFeature
    let incoming: Incoming

    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius ?? 14, style: .continuous)
        ViewThatFits(in: .vertical) {
            content(compact: false)
            content(compact: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            if theme.controls == nil {
                shape.fill(
                    LinearGradient(
                        colors: [theme.color(.accent).opacity(0.24), theme.color(.ink).opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: theme.color(.accent).opacity(0.28), radius: 12)
            }
        }
        .themePlatter(theme.controls == nil ? 0 : 0.08, in: shape)
        .buttonStyle(.plain)
        .help(incoming.text == nil ? incoming.offer?.detail ?? "" : "")
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func content(compact: Bool) -> some View {
        if let text = incoming.text {
            received(text, compact: compact)
        } else if let offer = incoming.offer {
            if let progress = incoming.progress {
                receiving(offer, progress: progress, compact: compact)
            } else {
                request(offer, compact: compact)
            }
        }
    }

    private func request(_ offer: InboundSession.Offer, compact: Bool) -> some View {
        arrange(
            compact: compact,
            head: head(offer.kind.symbol, offer.device, Text("wants to send \(offer.what)"), compact: compact),
            leading: code(offer.pin),
            buttons: HStack(spacing: 6) {
                CapsuleButton("Decline", prominent: false, action: transfer.declineIncoming)
                CapsuleButton("Accept", prominent: true, action: transfer.acceptIncoming)
            })
    }

    private func receiving(_ offer: InboundSession.Offer, progress: Double, compact: Bool) -> some View {
        arrange(
            compact: compact,
            head: head(
                offer.kind.symbol, "Receiving from \(offer.device)",
                Text("\(offer.what.capitalizedFirst) · \(Int(progress * 100))%").monospacedDigit(), compact: compact),
            leading: ProgressView(value: progress).progressViewStyle(.linear).tint(theme.color(.ink))
                .frame(maxWidth: compact ? 72 : .infinity)
                .accessibilityLabel("Receiving"),
            buttons: CapsuleButton("Cancel", prominent: false, action: transfer.cancelIncoming))
    }

    private func received(_ text: ReceivedText, compact: Bool) -> some View {
        arrange(
            compact: compact,
            head: head(
                text.isLink ? "link" : "text.alignleft", "\(incoming.device) sent \(text.isLink ? "a link" : "text")",
                ThemeLabel("Copied to the clipboard", symbol: "checkmark"), compact: compact),
            leading: Group {
                if !compact {
                    Text(text.text).themeFont(.body, size: 11).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled).foregroundStyle(.themeInk.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            },
            buttons: HStack(spacing: 6) {
                CapsuleButton("Done", prominent: !text.isLink, action: transfer.dismissText)
                if text.isLink { CapsuleButton("Open", prominent: true, action: transfer.openLink) }
            })
    }

    /// The device and two lines beside it; in one row, the lines alone, so the name has room.
    private func head(_ symbol: String, _ title: String, _ subtitle: some View, compact: Bool) -> some View {
        HStack(spacing: 10) {
            if !compact { DeviceBadge(symbol: symbol) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).themeFont(.display, size: 14, weight: .semibold).lineLimit(1)
                subtitle.themeFont(.body, size: 11).foregroundStyle(.themeSecondary).lineLimit(1)
            }
        }
    }

    /// The head over `leading` and the buttons, or all in one row.
    private func arrange(compact: Bool, head: some View, leading: some View, buttons: some View) -> some View {
        Group {
            if compact {
                HStack(spacing: 8) {
                    head
                    Spacer(minLength: 4)
                    leading
                    buttons
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    head
                    Spacer(minLength: 6)
                    HStack(alignment: .bottom, spacing: 6) {
                        leading
                        Spacer(minLength: 4)
                        buttons
                    }
                }
            }
        }
    }

    /// The code both screens show; a theme that picks with a block (Terminal) prints it inverted.
    private func code(_ pin: String) -> some View {
        let block = theme.controls?.selection == .block
        return VStack(alignment: .leading, spacing: 2) {
            Text("CODE").themeFont(.body, size: 9, weight: .semibold).kerning(0.7).foregroundStyle(.themeSecondary)
            Text(pin).themeFont(.numbers, size: 19, weight: .semibold, design: .rounded).monospacedDigit()
                .kerning(1.5)
                .foregroundStyle(block ? .themeOnAccent : .themeInk)
                .padding(.horizontal, block ? 4 : 0)
                .background {
                    if block { Rectangle().fill(.themeAccent) }
                }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code \(pin.map(String.init).joined(separator: " "))")
        .help("The same code shows on the phone")
    }
}

/// The device's symbol on a soft disc, as the notch's other cards show their subject.
private struct DeviceBadge: View {
    let symbol: String

    var body: some View {
        ThemeSymbol(symbol)
            .themeFont(.body, size: 15, weight: .medium)
            .frame(width: 32, height: 32)
            .themePlatter(0.12, in: Circle())
            .accessibilityHidden(true)
    }
}

/// The notch's buttons: a chip in the theme's shape, filled with the accent for the main action.
private struct CapsuleButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme

    init(_ title: String, prominent: Bool, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        let shape =
            theme.controls?.radius.map { AnyShape(RoundedRectangle(cornerRadius: $0, style: .continuous)) }
            ?? AnyShape(Capsule())
        Button(action: action) {
            Text(title)
                .themeFont(.body, size: 11, weight: .semibold)
                .fixedSize()  // a tight row truncates the device's name, never a button
                .foregroundStyle(prominent ? ThemeStyle.themeOnAccent : .themeSecondary)
                .padding(.horizontal, prominent ? 12 : 10)
                .frame(height: 26)
                .background {
                    if prominent { shape.fill(.themeAccent) }
                }
                .themePlatter(prominent ? 0 : 0.1, in: Capsule())
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

/// In the shelf's bar: receive for 10 minutes, how long is left, or that the Mac is visible.
private struct ReceiveControl: View {
    let transfer: TransferFeature

    var body: some View {
        Group {
            if transfer.localNetworkDenied {
                Button {
                    NSWorkspace.shared.open(.privacySettings("Privacy_LocalNetwork"))
                } label: {
                    ThemeLabel("Allow Local Network", symbol: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .help("macOS stops ILoveNotch from finding phones until Local Network is on for it")
            } else if let until = transfer.visibleUntil {
                Button(action: transfer.stopReceiving) {
                    Label {
                        let left = Text(timerInterval: .now...max(until, .now), countsDown: true).monospacedDigit()
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 4) {
                                Text("Visible for")
                                left
                            }
                            left
                        }
                    } icon: {
                        ThemeSymbol("dot.radiowaves.left.and.right")
                    }
                }
                .help("Android phones on this Wi-Fi can find this Mac. Click to stop.")
                .accessibilityLabel("Visible to Android. Stop")
            } else if transfer.isVisible {
                ThemeLabel("Visible", symbol: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.themeInk.opacity(0.6))
                    .help("Android phones on this Wi-Fi can send files to this Mac with Quick Share")
            } else {
                Button(action: transfer.receiveForTenMinutes) {
                    ThemeLabel("Receive", symbol: "dot.radiowaves.left.and.right")
                }
                .help("Let Android phones on this Wi-Fi find this Mac for 10 minutes")
                .accessibilityLabel("Receive from Android")
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.plain)
        .lineLimit(1)
    }
}

// MARK: - The send window

/// "Send to Android" opens its own window, as AirDrop does, so it stays up while the notch
/// closes and the user reaches for the phone to scan the code.
@MainActor
final class SendWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private weak var transfer: TransferFeature?

    init(transfer: TransferFeature) {
        self.transfer = transfer
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 480), styleMask: [.titled, .closable],
            backing: .buffered, defer: true)
        super.init()
        window.title = "Send to Android"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SendView(transfer: transfer) { [weak self] in self?.window.close() })
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        transfer?.closeSending()
    }
}

struct SendView: View {
    let transfer: TransferFeature
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let outgoing = transfer.outgoing {
                FilesSummary(files: outgoing.files)
                if outgoing.state == .picking {
                    picker
                } else {
                    status(outgoing)
                }
            }
        }
        .padding(20)
        .frame(width: 400, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Picking a device

    private var picker: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nearby").font(.headline)
                if transfer.localNetworkDenied {
                    localNetworkNotice
                } else if transfer.devices.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for phones on this Wi-Fi…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                } else {
                    VStack(spacing: 2) {
                        ForEach(transfer.devices) { device in
                            DeviceRow(device: device) { transfer.send(to: device) }
                        }
                    }
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 16) {
                if let url = transfer.qrCode?.url, let code = QRCodeImage.make(url) {
                    Image(nsImage: code)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .padding(8)
                        // A QR code reads on white; this is the Send window, not the notch.
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("QR code for Quick Share")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Phone not listed?").font(.headline)
                    Text("Scan this code with its camera. Quick Share opens, and the files go straight to it.")
                        .foregroundStyle(.secondary)
                    Text("Keep both on the same Wi-Fi.").font(.caption).foregroundStyle(.tertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
            }
        }
    }

    private var localNetworkNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Local network access is off for ILoveNotch", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Quick Share finds phones on your Wi-Fi, which macOS asks you to allow.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Open Privacy Settings") { NSWorkspace.shared.open(.privacySettings("Privacy_LocalNetwork")) }
        }
    }

    // MARK: Sending

    private func status(_ outgoing: Outgoing) -> some View {
        let name = outgoing.device?.name ?? "Android device"
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ThemeSymbol(outgoing.device?.kind.symbol ?? "smartphone")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.quaternary, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(detail(outgoing, name: name)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
                if let pin = outgoing.pin, outgoing.isBusy {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("CODE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(pin).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                            .kerning(1.5)
                    }
                    .help("Check it matches the code on the phone")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Code \(pin.map(String.init).joined(separator: " "))")
                }
            }
            switch outgoing.state {
            case .sending(let done):
                ProgressView(value: done).accessibilityLabel("Sending")
            case .connecting, .waiting:
                ProgressView().progressViewStyle(.linear)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .sent:
                Label("Sent", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .picking:
                EmptyView()
            }
            HStack {
                Spacer()
                switch outgoing.state {
                case .failed:
                    Button("Try Again", action: transfer.tryAgain)
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                case .sent:
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                default:
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private func detail(_ outgoing: Outgoing, name: String) -> String {
        switch outgoing.state {
        case .connecting: "Connecting…"
        case .waiting: "Waiting for it to be accepted…"
        case .sending(let done): "Sending… \(Int(done * 100))%"
        case .sent: "Sent"
        case .failed: "Not sent"
        case .picking: ""
        }
    }
}

/// The files going, with the first one's icon.
private struct FilesSummary: View {
    let files: [URL]

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: files[0].path))
                .resizable()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                let first = files[0].lastPathComponent
                Text(files.count == 1 ? first : "\(first) and \(files.count - 1) more")
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).foregroundStyle(.secondary)
            }
        }
    }

    private var size: Int64 {
        files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

private struct DeviceRow: View {
    let device: NearbyDevice
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ThemeSymbol(device.kind.symbol).font(.system(size: 16)).frame(width: 24)
                Text(device.name).lineLimit(1)
                Spacer()
                ThemeSymbol("chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(hovering ? 1 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Send to \(device.name)")
    }
}

/// Quick Share's QR code, drawn with Core Image's own generator.
private enum QRCodeImage {
    static func make(_ url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let representation = NSCIImageRep(ciImage: code)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

// MARK: - Settings

private struct TransferSettings: View {
    @Bindable var transfer: TransferFeature

    var body: some View {
        Group {
            Picker(selection: $transfer.receiveMode) {
                ForEach(TransferFeature.ReceiveMode.allCases) { Text($0.title).tag($0) }
            } label: {
                Text("Receive from Android")
                Text(
                    "Phones on the same Wi-Fi can send you files with Quick Share, set to Everyone. Nothing is saved until "
                        + "you accept in the notch.")
            }
            if transfer.receiveMode != .always {
                LabeledContent {
                    if let until = transfer.visibleUntil {
                        HStack {
                            Text(timerInterval: .now...max(until, .now), countsDown: true).monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button("Stop", action: transfer.stopReceiving)
                        }
                    } else {
                        Button("Be Visible", action: transfer.receiveForTenMinutes)
                    }
                } label: {
                    Text("Visible for 10 minutes")
                    Text("Also from Receive in the shelf.")
                }
            }
            TextField("Name on Android", text: $transfer.deviceName, prompt: Text(TransferFeature.computerName))
            LabeledContent {
                HStack {
                    Button("Choose\u{2026}", action: chooseFolder)
                    if transfer.folder != nil { Button("Use Downloads") { transfer.chooseFolder(nil) } }
                }
            } label: {
                Text("Save received files to")
                Text(transfer.saveFolder.lastPathComponent)
            }
            Toggle("Add received files to the shelf", isOn: $transfer.addsToShelf)
            if transfer.localNetworkDenied {
                LabeledContent("Local network access is off") {
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(.privacySettings("Privacy_LocalNetwork"))
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose where files from Android go."
        panel.directoryURL = transfer.saveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transfer.chooseFolder(url)
    }
}

extension InboundSession.Offer {
    /// "a photo", "3 photos", "2 files", "a link", or "text".
    var what: String {
        if let text { return text.kind == .url ? "a link" : "text" }
        let (one, many) =
            switch Set(files.map { $0.mimeType.prefix { $0 != "/" } }) {
            case ["image"]: ("a photo", "photos")
            case ["video"]: ("a video", "videos")
            default: ("a file", "files")
            }
        return files.count == 1 ? one : "\(files.count) \(many)"
    }

    /// The names and the size ("IMG_2041.jpg and IMG_2042.jpg · 6.8 MB"), or a link's title.
    var detail: String? {
        if let text { return text.title.isEmpty ? nil : text.title }
        let size = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "\(files.map(\.name).formatted(.list(type: .and))) · \(size)"
    }
}

extension String {
    /// "3 photos" stays, "a photo" becomes "A photo".
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

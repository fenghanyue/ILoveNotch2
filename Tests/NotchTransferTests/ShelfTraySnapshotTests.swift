// SPDX-License-Identifier: MIT
import AppKit
import Network
import NotchTheme
import SwiftUI
import Testing

@testable import NotchFeatures
@testable import NotchTransfer

/// The shelf's tray as the app shows it, Quick Share around it, in the theme `AUDIT_THEME` names
/// (Black without one): empty, then with real files, a missing one, and two picked, then with a
/// phone's offer. Always checks that it draws; with SNAPSHOT_DIR set, also writes PNGs there.
@MainActor
struct ShelfTraySnapshotTests {
    private static let size = CGSize(width: 428, height: 200)
    private static let smallest = CGSize(width: 350, height: 102)

    @Test func emptyThenFilledThenOffered() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShelfTray-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let transfer = TransferFeature(defaults: UserDefaults(suiteName: "ShelfTray-\(UUID())")!)
        let shelf = ShelfFeature(
            storeURL: folder.appending(path: "shelf.json"), pasteboard: NSPasteboard(name: .init("Tray.\(UUID())")))
        shelf.sendToAndroid = { _ in }
        shelf.androidControl = AnyView(transfer.receiveControl)
        let tray = transfer.shelfView(AnyView(shelf.view))
        try await render(tray, name: "shelf-tray-empty")

        let files = try Self.files(in: folder)
        shelf.add(files)
        try FileManager.default.removeItem(at: files[2])  // Notes from call.txt
        shelf.phase = .foreground
        shelf.select(shelf.items[3], adding: false)  // IMG_2041.jpg and Q4 Roadmap.md, in the first row
        shelf.select(shelf.items[5], adding: true)
        #expect(shelf.targets.count == 2)
        try await render(tray, name: "shelf-tray", waits: true)

        let photos = (0..<3).map {
            FileOffer(name: "IMG_20\(41 + $0).jpg", size: 3_400_000, mimeType: "image/jpeg", payloadID: Int64($0))
        }
        let offer = InboundSession.Offer(
            device: "Galaxy S25 Ultra", kind: .phone, pin: "4826", files: photos, text: nil, size: 10_200_000)
        let link = FrameLink(NWConnection(host: "127.0.0.1", port: 9, using: .tcp))
        transfer.show(incoming: Incoming(id: UUID(), link: link, offer: offer))
        try await render(tray, name: "shelf-tray-offer", waits: true)
    }

    /// Files Quick Look draws real thumbnails of, and some it only has icons for.
    private static func files(in folder: URL) throws -> [URL] {
        func write(_ name: String, _ data: Data?) throws -> URL {
            let url = folder.appending(path: name)
            try (data ?? Data(name.utf8)).write(to: url)
            return url
        }
        let folderURL = folder.appending(path: "Assets")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return [
            try write("Hero-Final@2x.png", picture([.systemIndigo, .systemOrange], type: .png)),
            try write("Invoice-November.pdf", invoice()),
            try write("Notes from call.txt", nil),
            try write("IMG_2041.jpg", picture([.systemGreen, .systemYellow], type: .jpeg)),
            try write("ilovenotch-1.5.1.dmg", Data(repeating: 7, count: 18_000)),
            try write("Q4 Roadmap.md", Data("# Q4 Roadmap\n\n- Shelf tray\n- Themes\n- Quick Share\n".utf8)),
            folderURL,
        ]
    }

    private static func picture(_ colors: [NSColor], type: NSBitmapImageRep.FileType) -> Data? {
        let image = NSImage(size: CGSize(width: 600, height: 400), flipped: false) { rect in
            NSGradient(colors: colors)?.draw(in: rect, angle: 35)
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: type, properties: [:])
    }

    /// A one-page PDF with a title bar and a few lines.
    private static func invoice() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
            let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return Data() }
        context.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.systemRed.setFill()
        NSRect(x: 72, y: 690, width: 220, height: 40).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22)]
        for (index, line) in ["Invoice", "November 2026", "Design work · 12 h", "Total due: $1,840"].enumerated() {
            (line as NSString).draw(at: CGPoint(x: 72, y: 620 - index * 48), withAttributes: attributes)
        }
        NSGraphicsContext.current = nil
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// At the default size and again at the smallest. `waits` gives Quick Look time to make thumbnails:
    /// an await, since the tiles' tasks need the main actor, which a run loop spun here would hold.
    private func render(_ view: some View, name: String, waits: Bool = false) async throws {
        try await render(view, name: name, size: Self.size, waits: waits)
        try await render(view, name: name + "-smallest", size: Self.smallest, waits: waits)
    }

    private func render(_ view: some View, name: String, size: CGSize, waits: Bool) async throws {
        let theme = Themes.theme(ProcessInfo.processInfo.environment["AUDIT_THEME"] ?? "black")
        let notch = view.frame(width: size.width, height: size.height).padding(16)
            .background(theme.surface.color.color)
            .foregroundStyle(.themeInk)
            .environment(\.colorScheme, theme.appearance.colorScheme)
            .environment(\.theme, theme)
        let host = NSHostingView(rootView: notch)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: size.width + 32, height: size.height + 32),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        if waits {
            try await Task.sleep(for: .seconds(1))
            host.layoutSubtreeIfNeeded()
        }
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

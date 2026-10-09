import AppKit
import SwiftUI
import CryptoKit

struct AdmissionEvidence {
    var receipts = Set<Int>()
    var expected: Int? = nil
    var actions = 0
    var state = "idle"
    var invalid = false
    mutating func receive(_ number: Int) {
        if !receipts.insert(number).inserted { invalid = true }
    }
    mutating func action(_ value: String, number: Int?, mouseUp: Bool) -> Bool {
        guard mouseUp, let number, number == expected,
              receipts.contains(number), receipts.contains(number - 1),
              !invalid, ["idle", "selected"].contains(value) else {
            invalid = true
            return false
        }
        actions += 1
        state = value
        expected = nil
        return true
    }
}

final class AdmissionModel: ObservableObject {
    @Published var text = "idle"
    var evidence = AdmissionEvidence()
    func act(_ value: String) {
        let event = NSApp.currentEvent
        if evidence.action(value, number: event?.eventNumber,
                           mouseUp: event?.type == .leftMouseUp) { text = value }
    }
}

enum AdmissionLayout {
    static let size = NSSize(width: 400, height: 200)
    // Shared top-left SwiftUI layout rectangles; events/capture convert from these.
    static let status = NSRect(x: 50, y: 40, width: 300, height: 40)
    static let select = NSRect(x: 20, y: 120, width: 100, height: 40)
    static let reset = NSRect(x: 150, y: 120, width: 100, height: 40)
    static let disabled = NSRect(x: 280, y: 120, width: 100, height: 40)
    static let padding = NSRect(x: 5, y: 5, width: 10, height: 10)
    static func hostingRect(_ rect: NSRect, in view: NSView) -> NSRect {
        NSRect(x: view.bounds.minX + rect.minX,
               y: view.bounds.minY + (view.isFlipped ? rect.minY : view.bounds.height - rect.maxY),
               width: rect.width, height: rect.height)
    }
}

extension View {
    func admissionBounds(_ rect: NSRect) -> some View {
        frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
    }
}

struct AdmissionView: View {
    @ObservedObject var model: AdmissionModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Text(model.text).font(.system(size: 24)).foregroundColor(.black)
                .admissionBounds(AdmissionLayout.status)
            Button("Select") { model.act("selected") }
                .admissionBounds(AdmissionLayout.select)
            Button("Reset") { model.act("idle") }
                .admissionBounds(AdmissionLayout.reset)
            Button("Disabled") { model.act("selected") }.disabled(true)
                .admissionBounds(AdmissionLayout.disabled)
        }.frame(width: AdmissionLayout.size.width, height: AdmissionLayout.size.height)
    }
}

final class AdmissionWindow: NSWindow {
    let model: AdmissionModel
    init(model: AdmissionModel) {
        self.model = model
        super.init(contentRect: NSRect(origin: .zero, size: AdmissionLayout.size),
                   styleMask: [.titled], backing: .buffered, defer: false)
    }
    override func sendEvent(_ event: NSEvent) {
        if event.windowNumber == windowNumber,
           [.leftMouseDown, .leftMouseUp].contains(event.type) {
            model.evidence.receive(event.eventNumber)
        }
        super.sendEvent(event)
    }
}

final class AdmissionDelegate: NSObject, NSApplicationDelegate {
    let model = AdmissionModel()
    var window: AdmissionWindow!
    var hosting: NSHostingView<AdmissionView>!
    var hashes: [String] = []
    var phase = 0
    var number = 100
    var done = false
    var timer: Timer?
    func visible() -> Bool {
        window.isVisible && !window.isMiniaturized && window.isKeyWindow &&
            NSApp.isActive && window.occlusionState.contains(.visible)
    }
    func render() -> String? {
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        // Only the fixed own synthetic status region, never desktop pixels.
        guard hosting.bounds.size == AdmissionLayout.size else { return nil }
        let region = AdmissionLayout.hostingRect(AdmissionLayout.status, in: hosting)
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: region) else { return nil }
        hosting.cacheDisplay(in: region, to: bitmap)
        guard let bytes = bitmap.bitmapData else { return nil }
        return SHA256.hash(data: Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh))
            .map { String(format: "%02x", $0) }.joined()
    }
    func finish(_ passed: Bool) {
        guard !done else { return }
        done = true
        timer?.invalidate()
        let record: [String: Any] = ["schema": 1, "result": passed ? "admitted" : "refused",
            "visible": visible(), "events": model.evidence.receipts.count == 8,
            "actions": model.evidence.actions == 2, "state_text": model.text == "idle",
            "negative": phase == 4 && !model.evidence.invalid, "render_hashes": hashes]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           data.count < 4096 { FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10])) }
        window.close()
        NSApp.stop(nil)
    }
    func queue(_ bounds: NSRect, action: Bool) {
        guard visible(), window.windowNumber > 0 else { finish(false); return }
        hosting.layoutSubtreeIfNeeded()
        guard hosting.bounds.size == AdmissionLayout.size else { finish(false); return }
        let actualBounds = AdmissionLayout.hostingRect(bounds, in: hosting)
        let point = hosting.convert(NSPoint(x: actualBounds.midX, y: actualBounds.midY), to: nil)
        number += 2
        model.evidence.expected = action ? number + 1 : nil
        let now = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: now, windowNumber: window.windowNumber,
            context: nil, eventNumber: number, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: now + 0.001, windowNumber: window.windowNumber,
            context: nil, eventNumber: number + 1, clickCount: 1, pressure: 0) else { finish(false); return }
        window.postEvent(down, atStart: false)
        window.postEvent(up, atStart: false)
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in self.advance() }
    }
    func advance() {
        guard !done, visible(), !model.evidence.invalid else { finish(false); return }
        guard let hash = render() else { finish(false); return }
        switch phase {
        case 0:
            hashes.append(hash); phase = 1; queue(AdmissionLayout.select, action: true)
        case 1:
            guard model.text == "selected", model.evidence.actions == 1, hash != hashes[0] else { finish(false); return }
            hashes.append(hash); phase = 2; queue(AdmissionLayout.reset, action: true)
        case 2:
            guard model.text == "idle", model.evidence.actions == 2, hash == hashes[0] else { finish(false); return }
            hashes.append(hash); phase = 3; queue(AdmissionLayout.padding, action: false)
        case 3:
            guard model.text == "idle", model.evidence.actions == 2, hash == hashes[0] else { finish(false); return }
            phase = 4; queue(AdmissionLayout.disabled, action: false)
        default:
            finish(model.text == "idle" && hash == hashes[0] && model.evidence.actions == 2 &&
                   model.evidence.receipts.count == 8)
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = AdmissionWindow(model: model)
        hosting = NSHostingView(rootView: AdmissionView(model: model))
        window.contentView = hosting
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { _ in self.finish(false) }
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in self.advance() }
    }
}

#if !ADMISSION_TESTS
@main struct WindowAdmissionMain {
    static func main() {
        guard CommandLine.arguments == [CommandLine.arguments[0], "--admit"] else { return }
        let app = NSApplication.shared
        let delegate = AdmissionDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif

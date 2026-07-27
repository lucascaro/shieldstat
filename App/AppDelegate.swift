import AppKit
import SwiftUI
import OSLog
import ShieldStatCore

/// Owns the menu bar item directly.
///
/// `MenuBarExtra` was the first choice and did not render a visible item on
/// macOS 26.4 — neither as an HStack label nor as a single interpolated Text.
/// `NSStatusItem` is the escape hatch named when that choice was made: it gives
/// direct control over the button and, unlike MenuBarExtra, can report its own
/// geometry, so "is there an item at all" is answerable from a log instead of
/// from someone looking at their screen.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private(set) lazy var model = StatusModel(settings: settings)

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private static let log = Logger(subsystem: "dev.lucascaro.ShieldStat", category: "menubar")


    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.imagePosition = .imageLeading

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: StatusPanel(model: model, settings: settings)
        )

        model.onUpdate = { [weak self] in self?.refreshButton() }
        model.start()
        refreshButton()

        Task { await model.notifierAuthorization() }
    }

    /// The menu bar item is the app; the settings window is incidental.
    ///
    /// Without this, closing the settings window quits ShieldStat outright: the
    /// only SwiftUI Scene is that Window, so once it closes SwiftUI sees no
    /// windows left and terminates. It looks exactly like a crash — the item
    /// vanishes with no fault, no crash report and nothing on stderr, because
    /// it is an orderly exit rather than a fault.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func refreshButton() {
        guard let button = statusItem?.button else {
            Self.log.error("status item has no button — nothing will be visible")
            return
        }

        let severity = model.observedSeverity
        let image = NSImage(
            systemSymbolName: severity.symbolName,
            accessibilityDescription: model.verdict.state.title
        )

        // Colour is carried in addition to the shape difference, never instead
        // of it. Tinting opts out of the template rendering that would otherwise
        // follow the menu bar's own appearance — the price of a traffic light.
        button.image = image?.withSymbolConfiguration(.init(paletteColors: [severity.menuBarTint]))
        button.image?.isTemplate = false

        button.title = showsLabel ? " \(model.verdict.state.shortLabel)" : ""
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [.foregroundColor: severity.menuBarTint]
        )

        Self.log.notice("""
            statusItem visible=\(self.statusItem?.isVisible ?? false, privacy: .public) \
            length=\(self.statusItem?.length ?? -1, privacy: .public) \
            buttonWidth=\(button.frame.width, privacy: .public) \
            windowOnScreen=\(button.window?.isVisible ?? false, privacy: .public) \
            symbol=\(severity.symbolName, privacy: .public) \
            symbolResolved=\(button.image != nil, privacy: .public) \
            title=\(button.title, privacy: .public)
            """)
    }

    private var showsLabel: Bool {
        switch settings.labelDisplay {
        case .always: true
        case .never: false
        case .alertsOnly: model.observedSeverity == .alert
        case .whenNotOK: model.observedSeverity != .ok
        }
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
        }
    }
}

import SwiftUI
import UserNotifications

@main
struct HABarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }  // the UI lives in AppDelegate's status item popover
    }
}

/// AppKit status item + popover rather than MenuBarExtra: NSPopover can be opened from code,
/// which launching the app from Spotlight/Raycast needs.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    let ha = HAClient()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var closedAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.delegate = self
        item.button?.target = self
        item.button?.action = #selector(toggle)
        trackIcon()
        trackAppearance()
        UNUserNotificationCenter.current().delegate = self
    }

    // Banners show even while the popover (so the app) is active; clicking one opens the popover.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound, .list] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let link = (response.notification.request.content.userInfo["url"] as? String).flatMap(URL.init(string:))
        await MainActor.run {
            if let link { NSWorkspace.shared.open(link) } else { show() }  // same tap target as on the phone
        }
    }

    /// NSPopover takes the menu bar's appearance, not the app's: apply the Theme setting to it directly.
    private func trackAppearance() {
        withObservationTracking {
            _ = ha.appearance
        } onChange: { [weak self] in
            // onChange fires before the new value lands; by the next main-actor turn NSApp.appearance is updated
            Task { @MainActor in
                self?.popover.appearance = NSApp.effectiveAppearance
                self?.trackAppearance()
            }
        }
    }

    /// Re-renders the status item image whenever a value it shows changes.
    private func trackIcon() {
        withObservationTracking {
            item.button?.image = menuBarImage(ha)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackIcon() }
        }
    }

    @objc private func toggle() {
        // a click on the button first closes the transient popover; don't reopen it right away
        guard Date().timeIntervalSince(closedAt) > 0.3 else { return }
        popover.isShown ? popover.performClose(nil) : show()
    }

    private func show() {
        guard !popover.isShown, let button = item.button else { return }
        NSApp.activate()
        popover.appearance = NSApp.effectiveAppearance  // "Auto" follows the system as it is right now
        // Built on every open, dropped on close: a closed popover would otherwise keep 30-90 MB of rendering alive.
        // Data (states, camera frames) lives in HAClient, so this only redraws.
        let host = NSHostingController(rootView: PopoverView().environment(ha))
        host.sizingOptions = .preferredContentSize  // popover follows the SwiftUI content size
        host.view.layoutSubtreeIfNeeded()  // measured before it's on screen: no grow-in jump
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Launching the app again opens the popover: `open -a` sends reopen, Spotlight/Raycast only activate.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        show()
    }

    func popoverDidShow(_ notification: Notification) {
        ha.isOpen = true
        ha.reconnectIfNeeded()
    }

    func popoverDidClose(_ notification: Notification) {
        ha.isOpen = false
        closedAt = Date()
        popover.contentViewController = nil
    }
}

/// Status item image, rendered as a template so it adapts to the menu bar.
@MainActor
func menuBarImage(_ ha: HAClient) -> NSImage {
        let count = ha.badgeCount
        let items = ha.tiles.filter { $0.inMenuBar && $0.kind != .camera }
        let showBadge = ha.menuShowBadge && count > 0
        let showHouse = ha.menuShowHouse || (items.isEmpty && !showBadge)  // never leave the status item empty
        let content = HStack(spacing: 7) {
            if showHouse || showBadge {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if showHouse { Image(systemName: "house.fill").font(.system(size: 13, weight: .semibold)) }
                    if showBadge { Text("\(count)").font(.system(size: 11, weight: .bold, design: .rounded)) }
                }
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, t in
                if i > 0 || showHouse || showBadge {
                    Capsule().frame(width: 1, height: 11).opacity(0.35)  // thin separator between groups
                }
                let e = ha.states[t.entityId]
                HStack(spacing: 3) {
                    Image(systemName: t.menuSymbol(e)).font(.system(size: 11.5, weight: .semibold))
                    if t.kind == .sensor { Text(e?.display ?? "—") }
                }
            }
        }
        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.black)
        .padding(.vertical, 1)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
}

enum Page { case dashboard, inbox, settings, picker }

struct PopoverView: View {
    @Environment(HAClient.self) private var ha
    @State private var page = Page.dashboard

    var body: some View {
        VStack(spacing: 16) {
            Header(page: $page)
            Group {
                switch page {
                case .dashboard: Dashboard()
                case .inbox: InboxView()
                case .settings: SettingsView(page: $page)
                case .picker: EntityPicker()
                }
            }
            .transition(.blurReplace)
        }
        .padding(16)
        .frame(width: 380)
        .animation(.smooth, value: page)
        .environment(\.locale, Lang.shared.current.locale)
        .onAppear { if ha.token.isEmpty { page = .settings } }
    }
}


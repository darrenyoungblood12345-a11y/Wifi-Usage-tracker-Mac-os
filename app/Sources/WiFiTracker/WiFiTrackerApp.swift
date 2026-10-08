import AppKit
import SwiftUI

@main
struct WiFiTrackerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuBarPopover()
        .environment(appDelegate.monitor)
    } label: {
      MenuBarLabel()
        .environment(appDelegate.monitor)
    }
    .menuBarExtraStyle(.window)

    Window("WiFi Tracker", id: WindowID.dashboard) {
      DashboardView()
        .environment(appDelegate.monitor)
    }
    .defaultSize(width: 980, height: 820)
    .windowResizability(.contentMinSize)

    Settings {
      SettingsView()
        .environment(appDelegate.monitor)
    }
  }
}

enum WindowID {
  static let dashboard = "dashboard"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let monitor = TrafficMonitor(storeURL: DevOptions.storeURL)

  func applicationDidFinishLaunching(_ notification: Notification) {
    DevOptions.applyAppearance()
    monitor.start(tracksApps: !DevOptions.isSnapshotting)
  }

  /// Closing the dashboard keeps tracking from the menu bar.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}

/// Shows the app in the Dock and app switcher only while one of its windows is open.
struct DockPresence: ViewModifier {
  func body(content: Content) -> some View {
    content
      .onAppear {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
      }
      .onDisappear {
        NSApp.setActivationPolicy(.accessory)
      }
  }
}

extension View {
  func showsInDockWhileOpen() -> some View {
    modifier(DockPresence())
  }
}

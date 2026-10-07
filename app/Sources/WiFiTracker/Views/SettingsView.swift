import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WiFiTrackerCore

struct SettingsView: View {
  @Environment(TrafficMonitor.self) private var monitor
  @AppStorage(SettingsKey.rateUnit) private var unit = RateUnit.bytes
  @AppStorage(SettingsKey.menuBarStyle) private var menuBarStyle = MenuBarStyle.both
  @State private var launchAtLogin = LoginItem.isEnabled
  @State private var confirmingClear = false
  @State private var message: String?

  var body: some View {
    Form {
      Section("General") {
        Toggle("Open at login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, enabled in
            do {
              try LoginItem.setEnabled(enabled)
            } catch {
              message = "Couldn’t change login item: \(error.localizedDescription)"
              launchAtLogin = LoginItem.isEnabled
            }
          }
      }

      Section("Display") {
        Picker("Speed units", selection: $unit) {
          ForEach(RateUnit.allCases) { Text($0.label).tag($0) }
        }
        Picker("Menu bar shows", selection: $menuBarStyle) {
          ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
        }
      }

      Section("Network names") {
        LabeledContent("Location access") {
          if monitor.wifi.canReadNetworkNames {
            Text("Allowed").foregroundStyle(.secondary)
          } else {
            Button("Allow…") { monitor.wifi.requestNetworkNames() }
          }
        }
        Text("Needed by macOS to read the Wi-Fi name. Your location is never read.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Data") {
        LabeledContent("Stored at") {
          Button(UsageStore.defaultURL.deletingLastPathComponent().path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([UsageStore.defaultURL])
          }
          .buttonStyle(.link)
          .lineLimit(1)
          .truncationMode(.middle)
        }
        HStack {
          Button("Export CSV…", action: exportCSV)
          Spacer()
          Button("Clear History…", role: .destructive) { confirmingClear = true }
        }
        if let message {
          Text(message).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 480)
    .fixedSize(horizontal: false, vertical: true)
    .showsInDockWhileOpen()
    .confirmationDialog("Clear all usage history?", isPresented: $confirmingClear) {
      Button("Clear History", role: .destructive) {
        do {
          try monitor.clearHistory()
          message = "History cleared."
        } catch {
          message = "Couldn’t clear history: \(error)"
        }
      }
    } message: {
      Text("This permanently deletes every recorded minute. Tracking continues from now.")
    }
  }

  private func exportCSV() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "WiFi Usage \(Date.now.formatted(.iso8601.year().month().day())).csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try monitor.exportCSV().write(to: url, atomically: true, encoding: .utf8)
      message = "Exported to \(url.lastPathComponent)."
    } catch {
      message = "Export failed: \(error.localizedDescription)"
    }
  }
}

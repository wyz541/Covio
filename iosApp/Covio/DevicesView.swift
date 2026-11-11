import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let local = model.localDevice {
                    Section("This device") {
                        LabeledContent("Name", value: local.displayName)
                        LabeledContent("System", value: local.systemName)
                        LabeledContent("Version", value: local.systemVersion)
                        LabeledContent("Model", value: local.model)
                        LabeledContent("Status", value: "Online")
                        LabeledContent("Capabilities", value: local.capabilities.joined(separator: ", "))
                    }
                }

                Section("Paired devices") {
                    if model.devices.isEmpty {
                        Text("No paired devices.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.devices) { device in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(device.displayName).font(.headline)
                                Spacer()
                                Text(device.online ? "Online" : "Offline")
                                    .foregroundStyle(device.online ? Color.green : Color.secondary)
                            }
                            Text("System: \(device.systemName ?? "Not reported")")
                            Text("Version: \(device.systemVersion ?? "Not reported")")
                            Text("Capabilities: \(device.capabilities.isEmpty ? "None reported" : device.capabilities.joined(separator: ", "))")
                            Text("Last seen: \(Date(timeIntervalSince1970: Double(device.lastSeenMs) / 1_000).formatted())")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    NavigationLink("Pair a device") {
                        PairingView()
                    }
                }
            }
            .navigationTitle("Devices")
            .refreshable { await model.refreshDevices() }
        }
    }
}

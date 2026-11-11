import SwiftUI
import UniformTypeIdentifiers

struct SendView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section("File") {
                    Button {
                        showImporter = true
                    } label: {
                        Label(
                            model.selectedFile?.lastPathComponent ?? "Choose a file",
                            systemImage: "doc.badge.plus"
                        )
                    }
                    if let file = model.selectedFile {
                        LabeledContent("Ready", value: file.lastPathComponent)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Paired device") {
                    if model.devices.isEmpty {
                        Text("Pair a device first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Send to", selection: $model.selectedPeerId) {
                            ForEach(model.devices) { device in
                                Text(device.displayName).tag(Optional(device.deviceId))
                            }
                        }
                    }
                    Button("Send file") {
                        Task { await model.sendSelectedFile() }
                    }
                    .disabled(model.selectedFile == nil || model.selectedPeerId == nil)
                }

                let outgoing = model.transfers.filter { $0.direction == "send" }
                if !outgoing.isEmpty {
                    Section("Transfers") {
                        ForEach(outgoing) { transfer in
                            TransferRow(transfer: transfer)
                        }
                    }
                }
            }
            .navigationTitle("Send")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                Task { await model.selectFile(result) }
            }
            .refreshable { await model.refreshDevices() }
        }
    }
}

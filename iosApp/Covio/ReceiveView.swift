import SwiftUI

struct ReceiveView: View {
    @EnvironmentObject private var model: AppModel
    @State private var shareURL: ShareItem?

    var body: some View {
        NavigationStack {
            List {
                Section("Receive files") {
                    Text("Covio can receive while this app is open.")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await model.startReceiving() }
                    } label: {
                        Label(
                            model.listenerActive ? "Listening" : "Start listening",
                            systemImage: model.listenerActive ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right"
                        )
                    }
                    .disabled(model.listenerActive)
                    if let error = model.listenerError {
                        Text(error).foregroundStyle(.red)
                    }
                }

                if let incoming = model.pendingIncoming {
                    Section("Incoming file") {
                        LabeledContent("File", value: incoming.fileName ?? "Unnamed file")
                        LabeledContent("Size", value: ByteCountFormatter.string(
                            fromByteCount: Int64(incoming.totalBytes),
                            countStyle: .file
                        ))
                        HStack {
                            Button("Decline", role: .destructive) {
                                Task { await model.rejectIncoming(incoming) }
                            }
                            Spacer()
                            Button("Accept") {
                                Task { await model.acceptIncoming(incoming) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                let incoming = model.transfers.filter { $0.direction == "receive" }
                if !incoming.isEmpty {
                    Section("Transfers") {
                        ForEach(incoming) { transfer in
                            TransferRow(transfer: transfer) {
                                if let path = transfer.finalPath {
                                    shareURL = ShareItem(url: URL(fileURLWithPath: path))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Receive")
            .sheet(item: $shareURL) { item in
                ShareSheet(items: [item.url])
            }
        }
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

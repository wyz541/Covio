import SwiftUI

struct TransferRow: View {
    @EnvironmentObject private var model: AppModel
    let transfer: TransferView
    var shareAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(transfer.fileName ?? "File")
                    .font(.headline)
                Spacer()
                Text(stateLabel)
                    .font(.caption)
                    .foregroundStyle(stateColor)
            }
            ProgressView(value: Double(transfer.progressPercent), total: 100)
            Text("\(ByteCountFormatter.string(fromByteCount: Int64(transfer.durableBytes), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(transfer.totalBytes), countStyle: .file))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = transfer.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                if transfer.state == "paused" || transfer.state == "background_deferred" || transfer.state == "waiting_network" {
                    Button("Resume") { Task { await model.resume(transfer) } }
                }
                if transfer.state == "completed", let shareAction {
                    Button("Share", action: shareAction)
                }
                Spacer()
                if !["completed", "failed", "cancelled", "rejected"].contains(transfer.state) {
                    Button("Cancel", role: .destructive) {
                        Task { await model.cancel(transfer) }
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var stateLabel: String {
        switch transfer.state {
        case "offer_waiting": return "Waiting for receiver"
        case "awaiting_acceptance": return "Confirm"
        case "transferring": return "Transferring"
        case "paused": return "Paused"
        case "background_deferred": return "Paused in background"
        case "waiting_network": return "Waiting for network"
        case "verifying": return "Verifying"
        case "committing": return "Saving"
        case "completed": return "Complete"
        case "failed": return "Failed"
        case "cancelled": return "Cancelled"
        case "rejected": return "Declined"
        case "expired": return "Expired"
        default: return transfer.state
        }
    }

    private var stateColor: Color {
        switch transfer.state {
        case "completed": return .green
        case "failed", "cancelled", "rejected", "expired": return .red
        case "paused", "background_deferred", "waiting_network": return .orange
        default: return .secondary
        }
    }
}

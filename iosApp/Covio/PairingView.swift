import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var scannerMode: ScannerMode?

    enum ScannerMode: Identifiable, Hashable {
        case offer
        case response
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let offer = model.pairingOfferQR {
                    QRCodePanel(title: "Scan on the other device", payload: offer)
                    Button("Scan response QR") { scannerMode = .response }
                        .buttonStyle(.borderedProminent)
                } else if let response = model.pairingResponseQR {
                    QRCodePanel(title: "Scan on the first device", payload: response)
                    if let code = model.confirmationCode {
                        ConfirmationCodePanel(code: code)
                    }
                    Button("Confirm on this device") {
                        Task { await model.confirmPairing() }
                    }
                    .buttonStyle(.borderedProminent)
                } else if let code = model.confirmationCode {
                    ConfirmationCodePanel(code: code)
                    Text("Compare the code on both devices before you confirm.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Confirm on this device") {
                        Task { await model.confirmPairing() }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ContentUnavailableView(
                        "Pair a device",
                        systemImage: "qrcode",
                        description: Text("Show a pairing QR or scan one from another Covio device.")
                    )
                    Button("Show pairing QR") {
                        Task { await model.beginPairing() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Scan pairing QR") { scannerMode = .offer }
                }
                if model.pairingOfferQR != nil || model.pairingResponseQR != nil || model.confirmationCode != nil {
                    Button("Cancel pairing", role: .cancel) {
                        Task { await model.cancelPairing() }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Pair a device")
        .sheet(item: $scannerMode) { mode in
            QRScannerView { value in
                scannerMode = nil
                Task {
                    switch mode {
                    case .offer:
                        await model.acceptPairingOffer(value)
                    case .response:
                        await model.completePairingWithResponse(value)
                    }
                }
            }
        }
    }
}

private struct ConfirmationCodePanel: View {
    let code: String

    var body: some View {
        VStack(spacing: 8) {
            Text("Confirmation code")
                .font(.headline)
            Text(code)
                .font(.system(size: 42, weight: .semibold, design: .monospaced))
                .tracking(6)
                .accessibilityLabel("Confirmation code \(code)")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

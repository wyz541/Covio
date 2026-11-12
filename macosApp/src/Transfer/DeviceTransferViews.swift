import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

enum DeviceTransferSection: String, CaseIterable, Identifiable {
    case pair
    case send
    case receive
    case devices

    var id: String { rawValue }
}

struct DeviceTransferBar: View {
    @ObservedObject var model: DeviceTransferModel
    let language: AppLanguage
    @State private var section: DeviceTransferSection?

    var body: some View {
        HStack(spacing: MacTheme.space3) {
            Label(
                DeviceTransferCopy.devices.text(for: language),
                systemImage: "laptopcomputer.and.iphone"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MacTheme.textPrimary)

            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: MacTheme.space2)

            MacButton(title: DeviceTransferCopy.pair.text(for: language)) {
                section = .pair
            }
            MacButton(title: DeviceTransferCopy.send.text(for: language)) {
                section = .send
            }
            MacButton(title: DeviceTransferCopy.receive.text(for: language)) {
                section = .receive
            }
        }
        .padding(.horizontal, MacTheme.space3)
        .frame(minHeight: 40)
        .background(
            MacTheme.material,
            in: RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                .strokeBorder(MacTheme.divider, lineWidth: 1)
        )
        .task { await model.bootstrap() }
        .sheet(item: $section) { section in
            DeviceTransferSheet(
                model: model,
                language: language,
                initialSection: section
            )
        }
    }

    private var status: String {
        if !model.isReady {
            return DeviceTransferCopy.starting.text(for: language)
        }
        let paired = DeviceTransferCopy.pairedCount(model.devices.count, language: language)
        let listening = model.listenerActive
            ? DeviceTransferCopy.listening.text(for: language)
            : DeviceTransferCopy.notListening.text(for: language)
        return "\(paired) · \(listening)"
    }
}

struct DeviceTransferSheet: View {
    @ObservedObject var model: DeviceTransferModel
    let language: AppLanguage
    @State private var section: DeviceTransferSection
    @Environment(\.dismiss) private var dismiss

    init(
        model: DeviceTransferModel,
        language: AppLanguage,
        initialSection: DeviceTransferSection
    ) {
        self.model = model
        self.language = language
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(DeviceTransferCopy.devices.text(for: language))
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help(DeviceTransferCopy.close.text(for: language))
            }
            .padding(.horizontal, MacTheme.space5)
            .padding(.top, MacTheme.space4)

            Picker("", selection: $section) {
                Text(DeviceTransferCopy.pair.text(for: language)).tag(DeviceTransferSection.pair)
                Text(DeviceTransferCopy.send.text(for: language)).tag(DeviceTransferSection.send)
                Text(DeviceTransferCopy.receive.text(for: language)).tag(DeviceTransferSection.receive)
                Text(DeviceTransferCopy.devices.text(for: language)).tag(DeviceTransferSection.devices)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, MacTheme.space5)
            .padding(.vertical, MacTheme.space4)

            Divider()

            ScrollView {
                sectionContent
                    .padding(MacTheme.space5)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if let error = model.errorMessage {
                HStack(alignment: .top, spacing: MacTheme.space3) {
                    MacAlert(message: error, kind: .error, language: language)
                    MacButton(title: DeviceTransferCopy.dismiss.text(for: language)) {
                        model.clearError()
                    }
                }
                .padding(MacTheme.space4)
            }
        }
        .frame(width: 760, height: 650)
        .background(MacTheme.surface)
        .onChange(of: section) { _, _ in model.clearError() }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .pair:
            DevicePairingPane(model: model, language: language)
        case .send:
            DeviceSendPane(model: model, language: language)
        case .receive:
            DeviceReceivePane(model: model, language: language)
        case .devices:
            DeviceListPane(model: model, language: language)
        }
    }
}

private struct DevicePairingPane: View {
    @ObservedObject var model: DeviceTransferModel
    let language: AppLanguage
    @State private var joinPayload = ""
    @State private var responsePayload = ""

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space4) {
            if let offer = model.pairingOfferQR {
                pairingOffer(offer)
            } else if let response = model.pairingResponseQR {
                pairingResponse(response)
            } else if let code = model.confirmationCode {
                confirmation(code)
            } else {
                pairingStart
            }
        }
    }

    private var pairingStart: some View {
        HStack(alignment: .top, spacing: MacTheme.space4) {
            MacCard {
                MacSectionTitle(text: DeviceTransferCopy.showQR.text(for: language))
                Text(DeviceTransferCopy.showQRDetail.text(for: language))
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
                MacButton(
                    title: DeviceTransferCopy.createPairingQR.text(for: language),
                    kind: .primary
                ) {
                    Task { await model.beginPairing() }
                }
            }

            MacCard {
                MacSectionTitle(text: DeviceTransferCopy.joinWithQR.text(for: language))
                Text(DeviceTransferCopy.joinWithQRDetail.text(for: language))
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
                TextField(
                    DeviceTransferCopy.qrPayload.text(for: language),
                    text: $joinPayload,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                MacButton(
                    title: DeviceTransferCopy.usePayload.text(for: language),
                    kind: .secondary
                ) {
                    Task { await model.acceptPairingOffer(joinPayload) }
                }
                .disabled(joinPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func pairingOffer(_ offer: String) -> some View {
        VStack(alignment: .leading, spacing: MacTheme.space4) {
            DeviceTransferQRPanel(
                title: DeviceTransferCopy.scanOnOther.text(for: language),
                payload: offer,
                language: language
            )
            MacCard {
                MacSectionTitle(text: DeviceTransferCopy.scanResponse.text(for: language))
                Text(DeviceTransferCopy.scanResponseDetail.text(for: language))
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
                TextField(
                    DeviceTransferCopy.responsePayload.text(for: language),
                    text: $responsePayload,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                HStack {
                    MacButton(
                        title: DeviceTransferCopy.completePairing.text(for: language),
                        kind: .primary
                    ) {
                        Task { await model.completePairing(responsePayload: responsePayload) }
                    }
                    .disabled(responsePayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    MacButton(title: DeviceTransferCopy.cancel.text(for: language), kind: .plain) {
                        Task { await model.cancelPairing() }
                    }
                }
            }
        }
    }

    private func pairingResponse(_ response: String) -> some View {
        VStack(alignment: .leading, spacing: MacTheme.space4) {
            DeviceTransferQRPanel(
                title: DeviceTransferCopy.scanOnFirst.text(for: language),
                payload: response,
                language: language
            )
            if let code = model.confirmationCode {
                confirmation(code)
            }
        }
    }

    private func confirmation(_ code: String) -> some View {
        MacCard {
            MacSectionTitle(text: DeviceTransferCopy.compareCode.text(for: language))
            Text(code)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
            Text(DeviceTransferCopy.confirmDetail.text(for: language))
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
            HStack {
                MacButton(
                    title: DeviceTransferCopy.confirmPairing.text(for: language),
                    kind: .primary
                ) {
                    Task { await model.confirmPairing() }
                }
                MacButton(title: DeviceTransferCopy.cancel.text(for: language), kind: .plain) {
                    Task { await model.cancelPairing() }
                }
            }
        }
    }
}

private struct DeviceSendPane: View {
    @ObservedObject var model: DeviceTransferModel
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space4) {
            MacCard {
                MacSectionTitle(text: DeviceTransferCopy.file.text(for: language))
                HStack {
                    Text(model.selectedFile?.lastPathComponent ?? DeviceTransferCopy.noFile.text(for: language))
                        .font(.system(size: 12))
                        .foregroundStyle(
                            model.selectedFile == nil ? MacTheme.textSecondary : MacTheme.textPrimary
                        )
                    Spacer()
                    MacButton(title: DeviceTransferCopy.chooseFile.text(for: language)) {
                        chooseFile()
                    }
                }

                if model.devices.isEmpty {
                    MacAlert(
                        message: DeviceTransferCopy.pairFirst.text(for: language),
                        kind: .warning,
                        language: language
                    )
                } else {
                    Picker(
                        DeviceTransferCopy.sendTo.text(for: language),
                        selection: $model.selectedPeerId
                    ) {
                        ForEach(model.devices) { device in
                            Text(device.displayName).tag(Optional(device.deviceId))
                        }
                    }
                    .pickerStyle(.menu)
                }

                MacButton(
                    title: DeviceTransferCopy.sendFile.text(for: language),
                    kind: .primary
                ) {
                    Task { await model.sendSelectedFile() }
                }
                .disabled(model.selectedFile == nil || model.selectedPeerId == nil)
            }

            transferList(direction: "send")
        }
        .task { await model.refreshDevices() }
    }

    @ViewBuilder
    private func transferList(direction: String) -> some View {
        let filtered = model.transfers.filter { $0.direction == direction }
        if !filtered.isEmpty {
            DeviceTransferList(
                title: DeviceTransferCopy.transfers.text(for: language),
                transfers: filtered,
                model: model,
                language: language
            )
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.selectFile(url)
        }
    }
}

private struct DeviceReceivePane: View {
    @ObservedObject var model: DeviceTransferModel
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space4) {
            MacCard {
                MacSectionTitle(text: DeviceTransferCopy.receive.text(for: language))
                Text(DeviceTransferCopy.receiveDetail.text(for: language))
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
                HStack {
                    MacButton(
                        title: model.listenerActive
                            ? DeviceTransferCopy.listening.text(for: language)
                            : DeviceTransferCopy.startListening.text(for: language),
                        kind: model.listenerActive ? .secondary : .primary
                    ) {
                        Task { await model.startReceiving() }
                    }
                    .disabled(model.listenerActive)
                    if let directory = model.receiveDirectory {
                        MacButton(title: DeviceTransferCopy.showFolder.text(for: language), kind: .plain) {
                            NSWorkspace.shared.open(directory)
                        }
                    }
                }
                if let error = model.listenerError {
                    MacAlert(message: error, kind: .error, language: language)
                }
            }

            if let incoming = model.pendingIncoming {
                MacCard {
                    MacSectionTitle(text: DeviceTransferCopy.incomingFile.text(for: language))
                    MacStatusLine(text: incoming.fileName ?? DeviceTransferCopy.unnamedFile.text(for: language))
                    MacStatusLine(text: ByteCountFormatter.string(
                        fromByteCount: Int64(incoming.totalBytes),
                        countStyle: .file
                    ))
                    HStack {
                        MacButton(
                            title: DeviceTransferCopy.accept.text(for: language),
                            kind: .primary
                        ) {
                            Task { await model.acceptIncoming(incoming) }
                        }
                        MacButton(
                            title: DeviceTransferCopy.decline.text(for: language),
                            kind: .plain
                        ) {
                            Task { await model.rejectIncoming(incoming) }
                        }
                    }
                }
            }

            let received = model.transfers.filter { $0.direction == "receive" }
            if !received.isEmpty {
                DeviceTransferList(
                    title: DeviceTransferCopy.transfers.text(for: language),
                    transfers: received,
                    model: model,
                    language: language
                )
            }
        }
    }
}

private struct DeviceListPane: View {
    @ObservedObject var model: DeviceTransferModel
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space4) {
            if let local = model.localDevice {
                MacCard {
                    MacSectionTitle(text: DeviceTransferCopy.thisMac.text(for: language))
                    DeviceInfoRow(label: DeviceTransferCopy.name.text(for: language), value: local.displayName)
                    DeviceInfoRow(label: DeviceTransferCopy.system.text(for: language), value: local.systemName)
                    DeviceInfoRow(label: DeviceTransferCopy.version.text(for: language), value: local.systemVersion)
                    DeviceInfoRow(label: DeviceTransferCopy.model.text(for: language), value: local.model)
                    DeviceInfoRow(label: DeviceTransferCopy.status.text(for: language), value: DeviceTransferCopy.online.text(for: language))
                    DeviceInfoRow(
                        label: DeviceTransferCopy.capabilities.text(for: language),
                        value: local.capabilities.joined(separator: ", ")
                    )
                }
            }

            MacCard {
                HStack {
                    MacSectionTitle(text: DeviceTransferCopy.pairedDevices.text(for: language))
                    Spacer()
                    MacButton(title: DeviceTransferCopy.refresh.text(for: language), kind: .plain) {
                        Task { await model.refreshDevices() }
                    }
                }
                if model.devices.isEmpty {
                    Text(DeviceTransferCopy.noPairedDevices.text(for: language))
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                } else {
                    ForEach(model.devices) { device in
                        Divider()
                        VStack(alignment: .leading, spacing: MacTheme.space1) {
                            HStack {
                                Text(device.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(device.online
                                    ? DeviceTransferCopy.online.text(for: language)
                                    : DeviceTransferCopy.offline.text(for: language))
                                    .font(.system(size: 11))
                                    .foregroundStyle(device.online ? MacTheme.successText : MacTheme.textSecondary)
                            }
                            MacStatusLine(text: "\(DeviceTransferCopy.system.text(for: language)): \(device.systemName ?? DeviceTransferCopy.notReported.text(for: language))")
                            MacStatusLine(text: "\(DeviceTransferCopy.version.text(for: language)): \(device.systemVersion ?? DeviceTransferCopy.notReported.text(for: language))")
                            MacStatusLine(text: "\(DeviceTransferCopy.lastSeen.text(for: language)): \(Self.date(device.lastSeenMs))")
                            MacStatusLine(text: "\(DeviceTransferCopy.capabilities.text(for: language)): \(device.capabilities.joined(separator: ", "))")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private static func date(_ milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000).formatted()
    }
}

private struct DeviceInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MacTheme.space3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textPrimary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct DeviceTransferList: View {
    let title: String
    let transfers: [DeviceTransferItem]
    @ObservedObject var model: DeviceTransferModel
    let language: AppLanguage

    var body: some View {
        MacCard {
            MacSectionTitle(text: title)
            ForEach(transfers) { transfer in
                Divider()
                DeviceTransferRow(transfer: transfer, model: model, language: language)
            }
        }
    }
}

private struct DeviceTransferRow: View {
    let transfer: DeviceTransferItem
    @ObservedObject var model: DeviceTransferModel
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            HStack {
                Text(transfer.fileName ?? DeviceTransferCopy.unnamedFile.text(for: language))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(DeviceTransferCopy.state(transfer.state, language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(stateColor)
            }
            ProgressView(value: Double(transfer.progressPercent), total: 100)
            MacStatusLine(text: "\(Self.bytes(transfer.durableBytes)) / \(Self.bytes(transfer.totalBytes))")
            if let error = DeviceTransferCopy.error(transfer, language: language) {
                MacAlert(message: error, kind: .error, language: language)
            }
            HStack {
                if transfer.state == "transferring" {
                    MacButton(title: DeviceTransferCopy.pause.text(for: language), kind: .plain) {
                        Task { await model.pause(transfer) }
                    }
                }
                if ["paused", "background_deferred", "background_suspended", "waiting_network"].contains(transfer.state) {
                    MacButton(title: DeviceTransferCopy.resume.text(for: language), kind: .secondary) {
                        Task { await model.resume(transfer) }
                    }
                }
                if transfer.state == "completed", let path = transfer.finalPath {
                    MacButton(title: DeviceTransferCopy.showInFinder.text(for: language), kind: .plain) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
                Spacer()
                if !["completed", "failed", "cancelled", "rejected", "expired"].contains(transfer.state) {
                    MacButton(title: DeviceTransferCopy.cancel.text(for: language), kind: .plain) {
                        Task { await model.cancel(transfer) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var stateColor: Color {
        switch transfer.state {
        case "completed": MacTheme.successText
        case "failed", "cancelled", "rejected", "expired": MacTheme.errorText
        case "paused", "background_deferred", "background_suspended", "waiting_network": MacTheme.warningText
        default: MacTheme.textSecondary
        }
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
}

private struct DeviceTransferQRPanel: View {
    let title: String
    let payload: String
    let language: AppLanguage

    var body: some View {
        MacCard {
            MacSectionTitle(text: title)
            HStack(alignment: .top, spacing: MacTheme.space4) {
                Group {
                    if let image = Self.qrImage(payload) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "qrcode")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }
                .frame(width: 220, height: 220)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: MacTheme.mediumRadius))
                .accessibilityLabel(title)

                VStack(alignment: .leading, spacing: MacTheme.space3) {
                    Text(DeviceTransferCopy.qrHint.text(for: language))
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                    Text(payload)
                        .font(.system(size: 9, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(6)
                    MacButton(title: DeviceTransferCopy.copyPayload.text(for: language), kind: .secondary) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(payload, forType: .string)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static func qrImage(_ payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let image = CIContext().createCGImage(output, from: output.extent)
        else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

private enum DeviceTransferCopy {
    static let pair = ContractCopy.copyDeviceTransferPair
    static let send = ContractCopy.copyDeviceTransferSend
    static let receive = ContractCopy.copyDeviceTransferReceive
    static let devices = ContractCopy.copyDeviceTransferDevices
    static let starting = ContractCopy.copyDeviceTransferStarting
    static let listening = ContractCopy.copyDeviceTransferListening
    static let notListening = ContractCopy.copyDeviceTransferNotListening
    static let close = ContractCopy.copyDeviceTransferClose
    static let dismiss = ContractCopy.copyDeviceTransferDismiss
    static let showQR = ContractCopy.copyDeviceTransferShowQr
    static let showQRDetail = ContractCopy.copyDeviceTransferShowQrDetail
    static let createPairingQR = ContractCopy.copyDeviceTransferCreatePairingQr
    static let joinWithQR = ContractCopy.copyDeviceTransferJoinWithQr
    static let joinWithQRDetail = ContractCopy.copyDeviceTransferJoinWithQrDetail
    static let qrPayload = ContractCopy.copyDeviceTransferQrPayload
    static let responsePayload = ContractCopy.copyDeviceTransferResponsePayload
    static let usePayload = ContractCopy.copyDeviceTransferUsePayload
    static let scanOnOther = ContractCopy.copyDeviceTransferScanOnOther
    static let scanOnFirst = ContractCopy.copyDeviceTransferScanOnFirst
    static let scanResponse = ContractCopy.copyDeviceTransferScanResponse
    static let scanResponseDetail = ContractCopy.copyDeviceTransferScanResponseDetail
    static let completePairing = ContractCopy.copyDeviceTransferCompletePairing
    static let compareCode = ContractCopy.copyDeviceTransferCompareCode
    static let confirmDetail = ContractCopy.copyDeviceTransferConfirmDetail
    static let confirmPairing = ContractCopy.copyDeviceTransferConfirmPairing
    static let cancel = ContractCopy.copyDeviceTransferCancel
    static let file = ContractCopy.copyDeviceTransferFile
    static let noFile = ContractCopy.copyDeviceTransferNoFile
    static let chooseFile = ContractCopy.copyDeviceTransferChooseFile
    static let pairFirst = ContractCopy.copyDeviceTransferPairFirst
    static let sendTo = ContractCopy.copyDeviceTransferSendTo
    static let sendFile = ContractCopy.copyDeviceTransferSendFile
    static let transfers = ContractCopy.copyDeviceTransferTransfers
    static let receiveDetail = ContractCopy.copyDeviceTransferReceiveDetail
    static let startListening = ContractCopy.copyDeviceTransferStartListening
    static let showFolder = ContractCopy.copyDeviceTransferShowFolder
    static let incomingFile = ContractCopy.copyDeviceTransferIncomingFile
    static let unnamedFile = ContractCopy.copyDeviceTransferUnnamedFile
    static let accept = ContractCopy.copyDeviceTransferAccept
    static let decline = ContractCopy.copyDeviceTransferDecline
    static let thisMac = ContractCopy.copyDeviceTransferThisMac
    static let name = ContractCopy.copyDeviceTransferName
    static let system = ContractCopy.copyDeviceTransferSystem
    static let version = ContractCopy.copyDeviceTransferVersion
    static let model = ContractCopy.copyDeviceTransferModel
    static let status = ContractCopy.copyDeviceTransferStatus
    static let online = ContractCopy.copyDeviceTransferOnline
    static let offline = ContractCopy.copyDeviceTransferOffline
    static let capabilities = ContractCopy.copyDeviceTransferCapabilities
    static let pairedDevices = ContractCopy.copyDeviceTransferPairedDevices
    static let refresh = ContractCopy.copyDeviceTransferRefresh
    static let noPairedDevices = ContractCopy.copyDeviceTransferNoPairedDevices
    static let notReported = ContractCopy.copyDeviceTransferNotReported
    static let lastSeen = ContractCopy.copyDeviceTransferLastSeen
    static let pause = ContractCopy.copyDeviceTransferPause
    static let resume = ContractCopy.copyDeviceTransferResume
    static let showInFinder = ContractCopy.copyDeviceTransferShowInFinder
    static let copyPayload = ContractCopy.copyDeviceTransferCopyPayload
    static let qrHint = ContractCopy.copyDeviceTransferQrHint

    static func pairedCount(_ count: Int, language: AppLanguage) -> String {
        let label = ContractCopy.copyDeviceTransferPairedLabel.text(for: language)
        return language == .simplifiedChinese ? "\(label) \(count)" : "\(count) \(label)"
    }

    static func state(_ state: String, language: AppLanguage) -> String {
        let value: LocalizedCopy
        switch state {
        case "offer_waiting": value = ContractCopy.copyDeviceTransferStateOfferWaiting
        case "awaiting_acceptance": value = ContractCopy.copyDeviceTransferStateAwaitingAcceptance
        case "transferring": value = ContractCopy.copyDeviceTransferStateTransferring
        case "paused": value = ContractCopy.copyDeviceTransferStatePaused
        case "background_deferred": value = ContractCopy.copyDeviceTransferStateBackgroundSuspended
        case "background_suspended": value = ContractCopy.copyDeviceTransferStateBackgroundSuspended
        case "waiting_network": value = ContractCopy.copyDeviceTransferStateWaitingNetwork
        case "verifying": value = ContractCopy.copyDeviceTransferStateVerifying
        case "committing": value = ContractCopy.copyDeviceTransferStateCommitting
        case "completed": value = ContractCopy.copyDeviceTransferStateCompleted
        case "failed": value = ContractCopy.copyDeviceTransferStateFailed
        case "cancelled": value = ContractCopy.copyDeviceTransferStateCancelled
        case "rejected": value = ContractCopy.copyDeviceTransferStateRejected
        case "expired": value = ContractCopy.copyDeviceTransferStateExpired
        default: return state
        }
        return value.text(for: language)
    }

    static func error(_ transfer: DeviceTransferItem, language: AppLanguage) -> String? {
        guard let code = transfer.errorCode else { return nil }
        let message: LocalizedCopy
        switch code {
        case "storage_io_error":
            message = ContractCopy.copyDeviceTransferErrorStorageIo
        case "chunk_hash_mismatch", "file_hash_mismatch":
            message = ContractCopy.copyDeviceTransferErrorHashMismatch
        case "path_collision":
            message = ContractCopy.copyDeviceTransferErrorPathCollision
        case "target_exists":
            message = ContractCopy.copyDeviceTransferErrorTargetExists
        case "transport_offline", "waiting_network":
            message = ContractCopy.copyDeviceTransferErrorNetworkUnavailable
        case "resume_checkpoint_invalid":
            message = ContractCopy.copyDeviceTransferErrorResumeInvalid
        case "background_suspended":
            message = ContractCopy.copyDeviceTransferErrorBackgroundPaused
        default:
            let fallback = transfer.errorMessage ?? ContractCopy.copyDeviceTransferErrorTransferFailed.text(for: language)
            return "\(fallback) [\(code)]"
        }
        return "\(message.text(for: language)) [\(code)]"
    }
}

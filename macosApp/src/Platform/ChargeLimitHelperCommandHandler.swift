import Foundation

/// 把 helper 线上命令转成持续策略动作。
///
/// 调用方签名由 socket 层先校验。这里只做命令解析、范围检查和结果编码。
final class ChargeLimitHelperCommandHandler: @unchecked Sendable {
    private let runtime: ChargeLimitRuntimeControlling

    init(runtime: ChargeLimitRuntimeControlling) {
        self.runtime = runtime
    }

    /// 不是充电命令时返回 nil，交给现有 helper 分支处理。
    func handle(_ request: HelperRequest) -> HelperReply? {
        switch request.command {
        case HelperWire.shared.COMMAND_CHARGE_LIMIT_STATUS:
            return statusReply(requestId: request.requestId)
        case HelperWire.shared.COMMAND_CHARGE_LIMIT_CONFIGURE:
            guard let percent = request.payload["percent"].flatMap(Int.init) else {
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: "Missing charge limit"
                )
            }
            let activeDischarge = request.payload["activeDischarge"].flatMap(Bool.init) ?? false
            return configureReply(
                requestId: request.requestId,
                percent: percent,
                activeDischarge: activeDischarge
            )
        case HelperWire.shared.COMMAND_CHARGE_LIMIT_RESTORE:
            return restoreReply(requestId: request.requestId)
        default:
            return nil
        }
    }

    func prepareForInstallTransaction(requestId: String) -> HelperReply {
        restoreReply(requestId: requestId)
    }

    private func statusReply(requestId: String) -> HelperReply {
        switch runtime.status() {
        case .success(let status) where status.phase == "off" && status.userLimitPercent == 0:
            var result = resultMap(status)
            result["enabled"] = "false"
            return HelperWire.shared.success(
                requestId: requestId,
                result: result
            )
        case .success(let status):
            return HelperWire.shared.success(
                requestId: requestId,
                result: resultMap(status)
            )
        case .failure(let failure):
            return HelperWire.shared.failure(
                requestId: requestId,
                message: failure.description
            )
        }
    }

    private func configureReply(
        requestId: String,
        percent: Int,
        activeDischarge: Bool
    ) -> HelperReply {
        switch runtime.configure(
            userLimitPercent: percent,
            activeDischargeEnabled: activeDischarge
        ) {
        case .success(let status):
            return HelperWire.shared.success(
                requestId: requestId,
                result: resultMap(status)
            )
        case .failure(let failure):
            return HelperWire.shared.failure(
                requestId: requestId,
                message: failure.description
            )
        }
    }

    private func restoreReply(requestId: String) -> HelperReply {
        switch runtime.restore() {
        case .success:
            return HelperWire.shared.success(requestId: requestId, result: [:])
        case .failure(let failure):
            return HelperWire.shared.failure(
                requestId: requestId,
                message: failure.description
            )
        }
    }

    private func resultMap(_ status: ChargeLimitRuntimeStatus) -> [String: String] {
        var result = [
            "enabled": "true",
            "userLimitPercent": String(status.userLimitPercent),
            "chargingLatch": String(status.chargingLatch),
            "phase": status.phase,
            "bypassEngaged": String(status.bypassEngaged),
            "activeDischarge": String(status.activeDischargeEnabled),
            "activeDischargeSupported": String(status.activeDischargeSupported),
        ]
        if let target = status.effectiveTargetPercent {
            result["targetPercent"] = String(target)
        }
        if let original = status.original {
            if let featureState = original.featureState {
                result["originalFeatureState"] = String(featureState)
            }
            if let limit = original.limitPercent {
                result["originalLimitPercent"] = String(limit)
            }
            if let optimized = original.optimizedChargingEnabled {
                result["originalOptimizedChargingEnabled"] = String(optimized)
            }
        }
        return result
    }
}

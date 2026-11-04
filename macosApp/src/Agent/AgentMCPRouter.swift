import Foundation
import MLXLMCommon

struct AgentMCPRequest: Decodable, Sendable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

enum AgentMCPErrorCode: Int, Sendable {
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603
}

struct AgentMCPJSONRPCError: Error, Sendable, Equatable {
    let code: AgentMCPErrorCode
    let message: String
}

actor AgentMCPRouter {
    static let protocolVersion = "2025-06-18"

    private let gateway: AgentServiceGateway

    init(gateway: AgentServiceGateway) {
        self.gateway = gateway
    }

    func handle(_ request: AgentMCPRequest, sessionID: String) async -> JSONValue? {
        guard request.jsonrpc == "2.0" else {
            return errorResponse(
                id: request.id,
                error: AgentMCPJSONRPCError(
                    code: .invalidRequest,
                    message: "Invalid JSON-RPC version."
                )
            )
        }
        if request.id == nil {
            return nil
        }

        do {
            switch request.method {
            case "initialize":
                return successResponse(id: request.id, result: initializeResult())
            case "ping":
                return successResponse(id: request.id, result: .object([:]))
            case "tools/list":
                return successResponse(id: request.id, result: toolsListResult())
            case "tools/call":
                return try await toolsCallResult(request, sessionID: sessionID)
            default:
                throw AgentMCPJSONRPCError(
                    code: .methodNotFound,
                    message: "Method not found."
                )
            }
        } catch let error as AgentMCPJSONRPCError {
            return errorResponse(id: request.id, error: error)
        } catch {
            return errorResponse(
                id: request.id,
                error: AgentMCPJSONRPCError(
                    code: .internalError,
                    message: "Local service failed."
                )
            )
        }
    }

    private func initializeResult() -> JSONValue {
        .object([
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": .object([
                "tools": .object(["listChanged": .bool(false)]),
            ]),
            "serverInfo": .object([
                "name": .string("Covio"),
                "version": .string(CovioReleaseIdentity.APP_VERSION),
            ]),
            "instructions": .string(
                "Covio local services. Side effects require confirmation in the Covio app."
            ),
        ])
    }

    private func toolsListResult() -> JSONValue {
        let tools = AgentExternalToolPolicy.exposedToolNames.sorted().compactMap { name -> JSONValue? in
            guard let descriptor = AgentExternalToolPolicy.descriptor(named: name),
                  let function = descriptor.schema["function"] as? [String: any Sendable]
            else { return nil }
            let parameters = function["parameters"].map(JSONValue.from) ?? .object([:])
            let risk = AgentExternalToolPolicy.risk(for: descriptor)
            return .object([
                "name": .string(descriptor.name),
                "description": .string(descriptor.summary),
                "inputSchema": parameters,
                "annotations": .object([
                    "readOnlyHint": .bool(risk == .readOnly),
                    "destructiveHint": .bool(risk == .sideEffect),
                    "idempotentHint": .bool(false),
                ]),
            ])
        }
        return .object(["tools": .array(tools)])
    }

    private func toolsCallResult(
        _ request: AgentMCPRequest,
        sessionID: String
    ) async throws -> JSONValue {
        guard case .object(let params)? = request.params,
              case .string(let name)? = params["name"],
              case .object(let arguments)? = params["arguments"]
        else {
            throw AgentMCPJSONRPCError(
                code: .invalidParams,
                message: "tools/call requires a tool name and object arguments."
            )
        }
        guard AgentExternalToolPolicy.descriptor(named: name) != nil else {
            throw AgentMCPJSONRPCError(
                code: .invalidParams,
                message: "The requested service is not exposed to external agents."
            )
        }

        let resultText = await gateway.handleExternal(
            ToolCall(function: .init(name: name, arguments: arguments)),
            sessionID: sessionID
        )
        let result = try decodeServiceResult(resultText)
        var structured: [String: JSONValue] = [
            "ok": .bool(result.ok),
            "summary": .string(result.summary),
        ]
        if let data = result.data {
            structured["data"] = data
        }
        if let errorCode = result.errorCode {
            structured["errorCode"] = .string(errorCode.rawValue)
        }
        let pending = await gateway.pendingAction()
        if let pending,
           pending.source == .external(sessionID)
        {
            structured["status"] = .string("pendingConfirmation")
            structured["actionId"] = .string(pending.id)
        }

        return successResponse(
            id: request.id,
            result: .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(resultText),
                    ])
                ]),
                "structuredContent": .object(structured),
                "isError": .bool(!result.ok),
            ])
        )
    }


    private func decodeServiceResult(_ text: String) throws -> AgentServiceResult {
        guard let data = text.data(using: .utf8) else {
            throw AgentMCPJSONRPCError(code: .internalError, message: "Invalid service result.")
        }
        return try JSONDecoder().decode(AgentServiceResult.self, from: data)
    }

    private func successResponse(id: JSONValue?, result: JSONValue) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id ?? .null,
            "result": result,
        ])
    }

    private func errorResponse(id: JSONValue?, error: AgentMCPJSONRPCError) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id ?? .null,
            "error": .object([
                "code": .int(error.code.rawValue),
                "message": .string(error.message),
            ]),
        ])
    }
}

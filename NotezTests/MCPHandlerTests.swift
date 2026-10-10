import Foundation
import Testing
@testable import Notez

/// JSON-RPC framing and the tool catalogue that MCP clients (Claude Code etc.) see.
@Suite struct MCPHandlerTests {
    let store: TestStore
    let mcp: MCPHandler
    init() throws {
        store = try TestStore()
        mcp = MCPHandler(api: NotesAPI(context: store.context))
    }

    private func send(_ message: Any) throws -> Any? {
        let data = try JSONSerialization.data(withJSONObject: message)
        return try mcp.handle(data).map { try JSONSerialization.jsonObject(with: $0) }
    }

    private func request(_ method: String, _ params: [String: Any] = [:], id: Int = 1) throws -> [String: Any] {
        try #require(try send(["jsonrpc": "2.0", "id": id, "method": method, "params": params]) as? [String: Any])
    }

    private func result(_ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let response = try request(method, params)
        return try #require(response["result"] as? [String: Any], "\(response)")
    }

    private func errorCode(_ response: Any?) -> Int? {
        ((response as? [String: Any])?["error"] as? [String: Any])?["code"] as? Int
    }

    private func raw(_ json: String) throws -> Any? {
        try mcp.handle(Data(json.utf8)).map { try JSONSerialization.jsonObject(with: $0) }
    }

    @Test func malformedMessages() throws {
        #expect(errorCode(try raw("{oops")) == -32700)
        #expect(errorCode(try raw(#""just a string""#)) == -32600)
        #expect(errorCode(try raw("[1, 2]")) == -32600)
    }

    @Test func notificationsGetNoResponse() throws {
        #expect(try send(["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)
        #expect(try send([["jsonrpc": "2.0", "method": "notifications/initialized"]]) == nil)
    }

    @Test func batchesAnswerEachRequest() throws {
        let responses = try send([
            ["jsonrpc": "2.0", "id": 1, "method": "ping"],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "ping"],
        ]) as? [[String: Any]]
        #expect(responses?.compactMap { $0["id"] as? Int } == [1, 2])
    }

    @Test func initializeNegotiatesTheProtocolVersion() throws {
        let known = try result("initialize", ["protocolVersion": "2025-06-18"])
        #expect(known["protocolVersion"] as? String == "2025-06-18")
        let unknown = try result("initialize", ["protocolVersion": "1999-01-01"])
        #expect(unknown["protocolVersion"] as? String == "2025-11-25")
        #expect((unknown["serverInfo"] as? [String: Any])?["name"] as? String == "notez")
        #expect((unknown["instructions"] as? String)?.isEmpty == false)
    }

    @Test func unknownMethodsAreErrors() throws {
        #expect(errorCode(try request("resources/list")) == -32601)
        #expect(errorCode(try request("tools/call", ["name": "format_disk"])) == -32602)
    }

    @Test func toolCatalogueIsWellFormed() throws {
        let tools = try #require(try result("tools/list")["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        #expect(Set(names) == [
            "list_notes", "list_projects", "create_project", "update_project", "delete_project",
            "search_notes", "get_note", "create_note", "update_note", "delete_note",
        ])
        for tool in tools {
            let name = tool["name"] as? String ?? "?"
            let schema = try #require(tool["inputSchema"] as? [String: Any], "\(name)")
            let properties = schema["properties"] as? [String: Any] ?? [:]
            let required = schema["required"] as? [String] ?? []
            #expect(schema["type"] as? String == "object", "\(name)")
            #expect(Set(required).isSubset(of: properties.keys), "\(name) requires an undeclared property")
            #expect((tool["description"] as? String)?.isEmpty == false, "\(name)")
            let hints = try #require(tool["annotations"] as? [String: Any])
            #expect(hints["destructiveHint"] as? Bool == name.hasPrefix("delete_"), "\(name)")
            let readOnly = ["list_notes", "list_projects", "search_notes", "get_note"].contains(name)
            #expect(hints["readOnlyHint"] as? Bool == readOnly, "\(name)")
        }
    }

    @Test func toolCallsReturnTextAndStructuredContent() throws {
        let call = try result("tools/call", ["name": "create_note", "arguments": ["title": "From MCP", "markdown": "hi"]])
        #expect(call["isError"] as? Bool == false)
        let structured = try #require(call["structuredContent"] as? [String: Any])
        #expect(structured["title"] as? String == "From MCP")
        let text = try #require((call["content"] as? [[String: Any]])?.first?["text"] as? String)
        let decoded = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        #expect(decoded?["id"] as? String == structured["id"] as? String)
        #expect(store.count(Note.self) == 1)
    }

    @Test func toolFailuresAreResultsNotProtocolErrors() throws {
        // MCP wants tool errors in the result so the model can read and recover.
        let call = try result("tools/call", ["name": "get_note", "arguments": ["id": UUID().uuidString]])
        #expect(call["isError"] as? Bool == true)
        let message = (call["content"] as? [[String: Any]])?.first?["text"] as? String
        #expect(message?.contains("not found") == true)
    }
}

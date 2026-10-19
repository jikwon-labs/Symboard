import Foundation
import SymboardCore

// symboard-mcp: claude 가 --mcp-config 로 띄우는 stdio MCP 서버(8차 3번).
// 줄마다 JSON-RPC 한 메시지를 읽고, 도구 호출은 앱 소켓(SYMBOARD_SOCKET)에 부른 콘솔(SYMBOARD_CALLER)과 함께 넘긴다.
let env = ProcessInfo.processInfo.environment
let socketPath = env["SYMBOARD_SOCKET"] ?? ""
let caller = env["SYMBOARD_CALLER"] ?? ""
let server = MCPStdioServer { tool, args in
    BoardBridge.request(socketPath: socketPath, caller: caller, tool: tool, args: args)
}
while let line = readLine(strippingNewline: true) {
    if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
    if let out = server.handle(line: line) {
        FileHandle.standardOutput.write(Data((out + "\n").utf8))
    }
}

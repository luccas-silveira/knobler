// End-to-end self-check for the authenticated agent-request loopback API.
//
//   swiftc tools/agentrequest-api-check.swift -o /tmp/agentrequest-api-check \
//     && /tmp/agentrequest-api-check

import Foundation

struct AgentRequestAPICheckLauncher {
    static func main() throws {
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = [
            "swiftc", "-parse-as-library",
            "Knobler/AgentRequestModels.swift", "Knobler/AskModels.swift",
            "Knobler/NotchAPIServer.swift", "tools/agentrequest-api-server-check.swift",
            "-o", "/tmp/agentrequest-api-check-inner",
        ]
        try compiler.run()
        compiler.waitUntilExit()
        precondition(compiler.terminationStatus == 0, "server check did not compile")

        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/tmp/agentrequest-api-check-inner")
        try check.run()
        check.waitUntilExit()
        precondition(check.terminationStatus == 0, "server check failed")
    }
}

do {
    try AgentRequestAPICheckLauncher.main()
} catch {
    fatalError("agentrequest-api-check: \(error.localizedDescription)")
}

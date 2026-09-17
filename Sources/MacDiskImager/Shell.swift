import Foundation

struct ShellResult { let output: String; let error: String; let status: Int32 }

enum Shell {
    static func run(_ executable: String, _ arguments: [String]) throws -> ShellResult {
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
        let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
        try p.run(); p.waitUntilExit()
        return ShellResult(output: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                           error: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                           status: p.terminationStatus)
    }
    static func appleScriptQuote(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

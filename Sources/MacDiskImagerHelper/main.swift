import Foundation
import Darwin

func fail(_ message: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("ERROR " + message + "\n").utf8)); exit(code)
}
func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
func run(_ exe: String, _ args: [String]) -> Int32 {
    let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
    p.standardOutput = FileHandle.standardError; p.standardError = FileHandle.standardError
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return 127 }
}
func validateDisk(_ device: String, _ raw: String) {
    guard geteuid() == 0 else { fail("Helper nie ma praw root. Zainstaluj go ponownie.", 77) }
    let id = String(device.dropFirst(5))
    guard device == "/dev/" + id, raw == "/dev/r" + id, id.hasPrefix("disk"), id.dropFirst(4).allSatisfy({ $0.isNumber }) else { fail("Nieprawidłowa ścieżka dysku") }
    let r = Process(); r.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil"); r.arguments = ["info", "-plist", device]
    let pipe = Pipe(); r.standardOutput = pipe; r.standardError = FileHandle.standardError
    do { try r.run(); r.waitUntilExit() } catch { fail("diskutil info") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard r.terminationStatus == 0,
          let p = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          (p["Internal"] as? Bool) == false,
          (p["DeviceIdentifier"] as? String) == id else { fail("Odmowa: dozwolony jest tylko zewnętrzny dysk fizyczny") }
}

let a = CommandLine.arguments
if a.count != 5 { fail("Użycie: helper write|read|verify /dev/diskN /dev/rdiskN total") }
let mode = a[1], device = a[2], raw = a[3], total = UInt64(a[4]) ?? 0
validateDisk(device, raw)
if run("/usr/sbin/diskutil", ["unmountDisk", "force", device]) != 0 { fail("Nie można odmontować dysku") }

defer { _ = run("/usr/sbin/diskutil", ["eject", device]) }
let block = 4 * 1024 * 1024
var buffer = [UInt8](repeating: 0, count: block)
var done: UInt64 = 0
var lastReport = Date.distantPast

func report(force: Bool = false) {
    if force || Date().timeIntervalSince(lastReport) >= 0.25 { log("PROGRESS \(done)"); lastReport = Date() }
}

switch mode {
case "write":
    let outFD = open(raw, O_WRONLY | O_SYNC)
    if outFD < 0 { fail("open \(raw): \(String(cString: strerror(errno)))") }
    defer { fsync(outFD); close(outFD) }
    while true {
        let data = FileHandle.standardInput.readData(ofLength: block)
        if data.isEmpty { break }
        let wrote = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return 0 }
            var offset = 0
            while offset < data.count {
                let n = Darwin.write(outFD, base.advanced(by: offset), data.count - offset)
                if n <= 0 { return -1 }
                offset += n
            }
            return offset
        }
        if wrote < 0 { fail("write: \(String(cString: strerror(errno)))") }
        done += UInt64(wrote); report()
    }
    report(force: true)
case "read":
    let inFD = open(raw, O_RDONLY)
    if inFD < 0 { fail("open \(raw): \(String(cString: strerror(errno)))") }
    defer { close(inFD) }
    while total == 0 || done < total {
        let want = total == 0 ? block : min(block, Int(total - done))
        let n = Darwin.read(inFD, &buffer, want)
        if n < 0 { fail("read: \(String(cString: strerror(errno)))") }
        if n == 0 { break }
        FileHandle.standardOutput.write(Data(buffer[0..<n])); done += UInt64(n); report()
    }
    report(force: true)
case "verify":
    let inFD = open(raw, O_RDONLY)
    if inFD < 0 { fail("open \(raw): \(String(cString: strerror(errno)))") }
    defer { close(inFD) }
    var offset: UInt64 = 0
    while true {
        let expected = FileHandle.standardInput.readData(ofLength: block)
        if expected.isEmpty { break }
        var actual = [UInt8](repeating: 0, count: expected.count)
        var got = 0
        while got < expected.count {
            let n = actual.withUnsafeMutableBytes { ptr -> Int in
                guard let base = ptr.baseAddress else { return -1 }
                return Darwin.read(inFD, base.advanced(by: got), expected.count - got)
            }
            if n <= 0 { fail("verify read przy offset \(offset)") }
            got += n
        }
        if expected != Data(actual) { fail("Weryfikacja niezgodna przy offset \(offset)", 3) }
        offset += UInt64(expected.count); done = offset; report()
    }
    report(force: true); log("Weryfikacja OK")
default: fail("Nieznana operacja")
}

import Foundation

struct DiskDevice: Identifiable, Hashable {
    let id: String
    let devicePath: String
    let rawPath: String
    let name: String
    let size: UInt64
    let removable: Bool
    let internalDisk: Bool
    let readOnly: Bool

    var displayName: String {
        "\(name) — \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) (\(id))"
    }
}

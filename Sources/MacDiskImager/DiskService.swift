import Foundation

final class DiskService {
    func externalPhysicalDisks() throws -> [DiskDevice] {
        let result = try Shell.run("/usr/sbin/diskutil", ["list", "-plist", "external", "physical"])
        guard result.status == 0 else { throw NSError(domain: "MDI", code: 1, userInfo: [NSLocalizedDescriptionKey: result.error]) }
        guard let data = result.output.data(using: .utf8),
              let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entries = plist["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
        return entries.compactMap { e -> DiskDevice? in
            guard let id = e["DeviceIdentifier"] as? String else { return nil }
            return try? info(id)
        }.filter { !$0.internalDisk }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func allocatedPartitionSpan(for disk: DiskDevice) throws -> UInt64? {
        let result = try Shell.run("/usr/sbin/diskutil", ["list", "-plist", disk.devicePath])
        guard result.status == 0,
              let data = result.output.data(using: .utf8),
              let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        var identifiers: [String] = []
        func collect(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let identifier = dictionary["DeviceIdentifier"] as? String {
                    let prefix = disk.id + "s"
                    let suffix = identifier.dropFirst(prefix.count)
                    if identifier.hasPrefix(prefix), !suffix.isEmpty,
                       suffix.allSatisfy({ $0.isNumber }) {
                        identifiers.append(identifier)
                    }
                }
                for child in dictionary.values { collect(child) }
            } else if let array = value as? [Any] {
                for child in array { collect(child) }
            }
        }
        collect(plist)

        var lastByte: UInt64 = 0
        for identifier in Set(identifiers) {
            let infoResult = try Shell.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(identifier)"])
            guard infoResult.status == 0,
                  let infoData = infoResult.output.data(using: .utf8),
                  let info = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any] else {
                continue
            }
            let offset = (info["PartitionMapPartitionOffset"] as? NSNumber)?.uint64Value
                ?? (info["PartitionOffset"] as? NSNumber)?.uint64Value
                ?? 0
            let size = (info["TotalSize"] as? NSNumber)?.uint64Value ?? 0
            if size > 0 { lastByte = max(lastByte, offset + size) }
        }

        guard lastByte > 0 else { return nil }
        let mib: UInt64 = 1024 * 1024
        let safety: UInt64 = mib
        let rounded = ((lastByte + safety + mib - 1) / mib) * mib
        return min(max(rounded, 2 * mib), disk.size)
    }

    private func info(_ id: String) throws -> DiskDevice {
        let r = try Shell.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(id)"])
        guard r.status == 0, let d = r.output.data(using: .utf8),
              let p = try PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any] else {
            throw NSError(domain: "MDI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nie można odczytać \(id)"])
        }
        return DiskDevice(id: id, devicePath: "/dev/\(id)", rawPath: "/dev/r\(id)",
                          name: (p["MediaName"] as? String) ?? id,
                          size: (p["TotalSize"] as? NSNumber)?.uint64Value ?? 0,
                          removable: p["RemovableMedia"] as? Bool ?? false,
                          internalDisk: p["Internal"] as? Bool ?? true,
                          readOnly: p["MediaReadOnly"] as? Bool ?? false)
    }
}

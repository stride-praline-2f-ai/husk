// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Small, streaming, standard ZIP. PNGs are already compressed; stored members
/// avoid another compressor dependency and keep CRC/size verification explicit.
enum DiagnosticArchive {
    struct Entry { let name: String; let url: URL }
    enum Failure: Error { case unsafeEntry, changedFile, tooLarge, duplicate }
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var c = UInt32(value)
        for _ in 0..<8 { c = (c & 1) == 1 ? 0xedb88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    private static func checksum(_ url: URL, limit: Int) throws -> (UInt32, Int) {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var crc = UInt32.max, bytes = 0
        while let data = try handle.read(upToCount: 65_536), !data.isEmpty {
            bytes += data.count; guard bytes <= limit else { throw Failure.tooLarge }
            for byte in data { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 255)] }
        }
        return (crc ^ UInt32.max, bytes)
    }
    static func write(_ entries: [Entry], to output: URL, limit: Int = 32 * 1024 * 1024) throws {
        guard entries.count <= 48, limit > 0, limit <= 64 * 1024 * 1024,
              !FileManager.default.fileExists(atPath: output.path) else { throw Failure.tooLarge }
        let partial = output.appendingPathExtension("partial")
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else { throw Failure.changedFile }
        var finished = false
        defer { if !finished { try? FileManager.default.removeItem(at: partial) } }
        let handle = try FileHandle(forWritingTo: partial); defer { try? handle.close() }
        var offset = 0, central = Data(), names = Set<String>()
        func emit(_ data: Data) throws {
            guard offset + data.count <= limit else { throw Failure.tooLarge }
            try handle.write(contentsOf: data); offset += data.count
        }
        for entry in entries {
            let parts = entry.name.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.name.hasPrefix("/"), !parts.contains(".."), !parts.contains("."), !parts.contains(""),
                  entry.name.utf8.count <= 240 else { throw Failure.unsafeEntry }
            guard names.insert(entry.name).inserted else { throw Failure.duplicate }
            let resource = try entry.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard resource.isRegularFile == true, resource.isSymbolicLink != true else { throw Failure.unsafeEntry }
            let (crc, bytes) = try checksum(entry.url, limit: limit)
            let name = Data(entry.name.utf8), start = offset
            var local = Data(); local.le(UInt32(0x04034b50)); local.le(UInt16(20)); local.le(UInt16(0x800)); local.le(UInt16(0))
            local.le(UInt16(0)); local.le(UInt16(0x21)); local.le(crc); local.le(UInt32(bytes)); local.le(UInt32(bytes)); local.le(UInt16(name.count)); local.le(UInt16(0)); local.append(name)
            try emit(local)
            let source = try FileHandle(forReadingFrom: entry.url)
            var copied = 0, copiedCRC = UInt32.max
            do {
                while let data = try source.read(upToCount: 65_536), !data.isEmpty {
                    copied += data.count; guard copied <= bytes else { throw Failure.changedFile }
                    for byte in data { copiedCRC = (copiedCRC >> 8) ^ crcTable[Int((copiedCRC ^ UInt32(byte)) & 255)] }
                    try emit(data)
                }
                try source.close()
            } catch { try? source.close(); throw error }
            guard copied == bytes, (copiedCRC ^ UInt32.max) == crc else { throw Failure.changedFile }
            central.le(UInt32(0x02014b50)); central.le(UInt16(20)); central.le(UInt16(20)); central.le(UInt16(0x800)); central.le(UInt16(0))
            central.le(UInt16(0)); central.le(UInt16(0x21)); central.le(crc); central.le(UInt32(bytes)); central.le(UInt32(bytes)); central.le(UInt16(name.count))
            central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt32(0)); central.le(UInt32(start)); central.append(name)
        }
        let centralStart = offset; try emit(central)
        var end = Data(); end.le(UInt32(0x06054b50)); end.le(UInt16(0)); end.le(UInt16(0)); end.le(UInt16(entries.count)); end.le(UInt16(entries.count))
        end.le(UInt32(central.count)); end.le(UInt32(centralStart)); end.le(UInt16(0)); try emit(end)
        try handle.synchronize(); try handle.close()
        try FileManager.default.moveItem(at: partial, to: output); finished = true
    }
}
private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

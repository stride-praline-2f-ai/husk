// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

/// File-only codec/exporter, shared with real Apple component tests. No UIKit,
/// render queues or live GPU waits run during export.
enum FrameEvidenceFiles {
    enum Failure: LocalizedError {
        case unsafeFile, invalidImage, invalidMetadata, storageLimit, pngFailed
        var errorDescription: String? {
            switch self {
            case .unsafeFile: return "A diagnostic file has an unsupported path, type or size. Existing evidence is kept."
            case .invalidImage: return "A captured image is incomplete or has an unsupported pixel layout. Raw evidence is kept."
            case .invalidMetadata: return "Capture metadata is incomplete or unsupported. Raw evidence and logs are kept."
            case .storageLimit: return "The capture exceeds the bounded export limits. Raw evidence and logs are kept."
            case .pngFailed: return "A captured image could not be converted to PNG. Raw evidence is kept."
            }
        }
    }
    static func regular(_ url: URL, limit: Int) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
              size >= 0, size <= limit else { throw Failure.unsafeFile }
        return size
    }
    static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 65_536), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func png(raw: URL, metadata: [String: Any], to output: URL) throws {
        guard metadata["format"] as? String == "BGRA8Unorm", let width = metadata["width"] as? Int,
              let height = metadata["height"] as? Int, let row = metadata["row_bytes"] as? Int,
              (1...4096).contains(width), (1...4096).contains(height), row == ((width * 4 + 255) & ~255),
              try regular(raw, limit: 64 * 1024 * 1024) == row * height else { throw Failure.invalidImage }
        let bytes = try Data(contentsOf: raw, options: .mappedIfSafe)
        guard let provider = CGDataProvider(data: bytes as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: row, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let writer = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else { throw Failure.pngFailed }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw Failure.pngFailed }
    }
    private static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count < 100 && !name.contains("/") && !name.contains("\\") && !name.contains("..") && !name.hasPrefix(".")
    }
    static func bundle(capture: URL?, logs: [URL], context: Data, output: URL) throws {
        let fm = FileManager.default
        let work = output.deletingLastPathComponent().appendingPathComponent("work-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true); defer { try? fm.removeItem(at: work) }
        var entries: [DiagnosticArchive.Entry] = [], index: [[String: Any]] = [], omissions: [[String: Any]] = [], pairs: [[String: Any]] = []
        func add(_ source: URL, _ name: String) throws {
            let size = try regular(source, limit: 24 * 1024 * 1024)
            entries.append(.init(name: name, url: source)); index.append(["file": name, "bytes": size, "sha256": try digest(source)])
        }
        // Native timing metadata is atomically refreshed after late callbacks.
        // Freeze it once so bundle-index hashes and ZIP members describe the
        // SAME bytes even if that refresh overlaps the manual share action.
        func snapshot(_ source: URL, _ name: String) throws {
            _ = try regular(source, limit: 128 * 1024)
            let data = try Data(contentsOf: source)
            guard data.count <= 128 * 1024 else { throw Failure.storageLimit }
            let copy = work.appendingPathComponent(UUID().uuidString + ".json")
            try data.write(to: copy); try add(copy, name)
        }
        let contextURL = work.appendingPathComponent("export-context.json"); try context.write(to: contextURL); try add(contextURL, "export-context.json")
        if let capture {
            let parent = try capture.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard parent.isDirectory == true, parent.isSymbolicLink != true else { throw Failure.unsafeFile }
            let session = capture.appendingPathComponent("host-session.json")
            if fm.fileExists(atPath: session.path) { try snapshot(session, "capture/host-session.json") }
            let native = capture.appendingPathComponent("frames", isDirectory: true)
            if fm.fileExists(atPath: native.path) {
                let v = try native.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard v.isDirectory == true, v.isSymbolicLink != true else { throw Failure.unsafeFile }
                let names = try fm.contentsOfDirectory(atPath: native.path)
                guard names.count <= 30 else { throw Failure.storageLimit }
                for name in names.sorted() where name.hasSuffix(".json") || name == "engine-requests.txt" {
                    guard safeName(name) else { throw Failure.unsafeFile }
                    let url = native.appendingPathComponent(name); _ = try regular(url, limit: 128 * 1024)
                    try snapshot(url, "capture/" + name)
                    guard name.hasPrefix("pair-"), name.hasSuffix(".json") else { continue }
                    guard let record = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                          let files = record["files"] as? [[String: Any]], files.count <= 11 else { throw Failure.invalidMetadata }
                    pairs.append(["manifest": name, "state": record["state"] ?? "UNAVAILABLE", "stages_saved": files.count, "error": record["error"] ?? NSNull()])
                    for item in files {
                        guard let file = item["file"] as? String, safeName(file), file.hasPrefix("pair-") else { throw Failure.unsafeFile }
                        let raw = native.appendingPathComponent(file)
                        if file.hasSuffix(".bgra") {
                            let image = work.appendingPathComponent(file + ".png")
                            try png(raw: raw, metadata: item, to: image)
                            try add(image, "capture/" + file.replacingOccurrences(of: ".bgra", with: ".png"))
                            index.append(["raw_source_file": file, "archive_image_file": "capture/" + file.replacingOccurrences(of: ".bgra", with: ".png"),
                                          "raw_bytes": try regular(raw, limit: 64 * 1024 * 1024), "raw_sha256": try digest(raw),
                                          "representation": "Lossless RGB PNG; unused alpha omitted for opaque layer. Raw BGRA remains locally in Files."])
                        } else if file.hasSuffix(".f16") {
                            guard item["format"] as? String == "RGBA16Float", let width = item["width"] as? Int,
                                  let height = item["height"] as? Int, let row = item["row_bytes"] as? Int,
                                  (1...256).contains(width), (1...256).contains(height), row == ((width * 8 + 255) & ~255),
                                  try regular(raw, limit: 1024 * 1024) == row * height else { throw Failure.invalidMetadata }
                            try add(raw, "capture/" + file)
                        }
                        else if file.hasSuffix(".f32") {
                            guard item["format"] as? String == "RGBA32Float", item["width"] as? Int == 1,
                                  item["height"] as? Int == 1, item["row_bytes"] as? Int == 256,
                                  try regular(raw, limit: 256) == 256 else { throw Failure.invalidMetadata }
                            try add(raw, "capture/" + file)
                        }
                        else { throw Failure.unsafeFile }
                    }
                }
            }
        }
        for log in logs {
            guard safeName(log.lastPathComponent), fm.fileExists(atPath: log.path) else { continue }
            let length = try regular(log, limit: 256 * 1024 * 1024)
            let handle = try FileHandle(forReadingFrom: log); defer { try? handle.close() }
            let limit = 1024 * 1024
            var data: Data
            if length <= limit { data = try handle.read(upToCount: length) ?? Data() }
            else {
                data = try handle.read(upToCount: 32 * 1024) ?? Data()
                data.append(Data("\n[DIAGNOSTIC EXPORT TRUNCATED: header and tail retained; original remains in Files]\n".utf8))
                try handle.seek(toOffset: UInt64(length - (limit - 32 * 1024)))
                data.append(try handle.read(upToCount: limit - 32 * 1024) ?? Data())
                omissions.append(["file": log.lastPathComponent, "original_bytes": length, "reason": "bounded log export; header and tail retained"])
            }
            let copy = work.appendingPathComponent(log.lastPathComponent); try data.write(to: copy)
            try add(copy, "logs/" + log.lastPathComponent)
        }
        let manifest: [String: Any] = ["schema": 1, "plan_ids": ["M1", "M3", "M9"], "capture_present": capture != nil,
            "entries": index, "omissions": omissions, "capture_pairs": pairs, "complete_pairs": pairs.filter { $0["state"] as? String == "complete" }.count,
            "native_log_mirrored_in_husk_log": true,
            "scope": "Captured guest colour, generated/following-real RGB, raw flow fields, consumer timings and contextual logs where available. Missing stages remain unavailable.",
            "limitations": "Capture copies are intrusive. Requested engine CVars are not runtime readback. Logs and capture may have different session IDs; compare identities. No panel, input-latency, temperature or power measurement."]
        let manifestURL = work.appendingPathComponent("bundle-index.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: manifestURL)
        entries.append(.init(name: "bundle-index.json", url: manifestURL))
        try DiagnosticArchive.write(entries, to: output)
    }
}

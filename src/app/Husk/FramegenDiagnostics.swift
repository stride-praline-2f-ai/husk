// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import UIKit
import Metal

/// One explicit evidence request, never an automatic screenshot recorder.
@MainActor enum FramegenDiagnostics {
    private static var activeID: String?
    private static var lastLaunch: (appID: String, values: [String: Any])?
    static var root: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Frame Evidence", isDirectory: true) }
    private static var pending: URL { root.appendingPathComponent("pending.json") }
    private static var latest: URL { root.appendingPathComponent("latest.json") }
    private static var requiredContract: Any {
        guard let url = Bundle.main.url(forResource: "framegen-contract", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count < 128 * 1024,
              let value = try? JSONSerialization.jsonObject(with: data) else { return "UNAVAILABLE; FG must refuse" }
        return value
    }
    static var context: [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        var drivers: [String: Any] = [:]
        for (folder, file) in [("HuskKosmicKrisp.framework", "HuskMetal4Build.json"), ("KosmicKrisp.framework", "HuskMetal4Build.json"), ("HuskMoltenVK.framework", "HuskSpatialBuild.json")] {
            if let url = Bundle.main.privateFrameworksURL?.appendingPathComponent(folder).appendingPathComponent(file),
               let data = try? Data(contentsOf: url), data.count < 128 * 1024,
               let manifest = try? JSONSerialization.jsonObject(with: data) { drivers[folder] = manifest }
        }
        return ["schema": 1, "host_session_id": HuskLog.sessionID, "version": info["CFBundleShortVersionString"] ?? "UNAVAILABLE",
            "build": info["CFBundleVersion"] ?? "UNAVAILABLE", "source": info["HuskBuildCommit"] ?? "UNAVAILABLE", "built": info["HuskBuildDate"] ?? "UNAVAILABLE",
            "observed_unix_time": Date().timeIntervalSince1970, "host_monotonic_seconds": ProcessInfo.processInfo.systemUptime,
            "device": HuskLog.deviceModel, "os": UIDevice.current.systemVersion, "gpu": MTLCreateSystemDefaultDevice()?.name ?? "UNAVAILABLE",
            "physical_ram_bytes": ProcessInfo.processInfo.physicalMemory, "cpu_count": ProcessInfo.processInfo.processorCount,
            "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled, "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
            "application_state": UIApplication.shared.applicationState.rawValue, "drivers": drivers, "required_framegen_contract": requiredContract,
            "scope": "Host context at this observation time; capture frames have their own IDs/times. No electrical power or runtime engine CVar readback."]
    }
    private static func json(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    private static func folder(_ id: String) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return root.appendingPathComponent(id, isDirectory: true)
    }
    static var latestFolder: URL? {
        guard let data = try? Data(contentsOf: latest), let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = value["id"] else { return nil }
        return folder(id)
    }
    private static func savedSettings(_ id: String) -> Any {
        guard let data = try? JSONEncoder().encode(TLAppSettings.load(id)), let value = try? JSONSerialization.jsonObject(with: data) else { return "UNAVAILABLE" }
        return value
    }
    static func recordLaunch(apk: String, values: [String: Any]) {
        let appID = URL(fileURLWithPath: apk).deletingLastPathComponent().lastPathComponent
        lastLaunch = (appID, values)
        guard let dir = activeID.flatMap({ folder($0) }),
              let data = try? Data(contentsOf: dir.appendingPathComponent("host-session.json")),
              var record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              record["app_id"] as? String == appID else { return }
        record["effective_launch"] = values
        try? json(record, to: dir.appendingPathComponent("host-session.json"))
    }
    static func arm(app: TLApp, inUse: Bool) throws -> String {
        let fm = FileManager.default; try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID().uuidString, dir = folder(id)!, frames = dir.appendingPathComponent("frames", isDirectory: true)
        try fm.createDirectory(at: frames, withIntermediateDirectories: true)
        var record = context
        record["app_id"] = app.id; record["game"] = app.label; record["capture_id"] = id
        if let launch = lastLaunch, launch.appID == app.id { record["effective_launch"] = launch.values }
        record["saved_requested_settings"] = savedSettings(app.id); record["requested_engine_values"] = "requests only; actual runtime CVars unavailable"
        record["purpose"] = "Separate already-blurred guest input from framegen reconstruction and display timing; no screen recording needed"
        record["capture_overhead"] = "One pair; up to64MiB temporary staging; GPU readbacks/Utility file work are intrusive. Exclude these frames from performance comparisons."
        let result = inUse ? frames.path.withCString { tl_vk_framegen_capture_arm($0, 90, 90, 1) } : -1
        record["arm_result"] = result; record["state"] = result == 1 ? "armed_live" : (inUse ? "unavailable" : "queued_next_launch")
        try json(record, to: dir.appendingPathComponent("host-session.json"))
        if result == 1 || !inUse {
            if result == 1 { activeID = id }; try json(["id": id], to: latest)
            if !inUse { try json(["id": id, "app_id": app.id], to: pending) }
        }
        HuskLog.log("frame-evidence", "[M3/M9] \(record["state"]!); capture \(id), app \(app.id); local only, no automatic upload")
        prune(keeping: id)
        if result == 1 { return "Capture armed. Return to the scene only if comfortable; one matched pair saves after about 3 seconds of rendered frames. No recording needed." }
        if inUse { return "Capture is unavailable in the running renderer or another capture is busy. Keep existing files; use source Metal4 Enhancements with FG on if you later choose to capture." }
        return "One capture is queued for the next full game launch with FG enabled. No continuous recording. You do not need to keep watching if it is uncomfortable."
    }
    static func consume(apk: String) -> String? {
        guard let data = try? Data(contentsOf: pending), let request = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = request["id"], let appID = request["app_id"], let dir = folder(id) else { return nil }
        let apkURL = URL(fileURLWithPath: apk).standardizedFileURL
        guard apkURL.deletingLastPathComponent().lastPathComponent == appID else { return nil }
        try? FileManager.default.removeItem(at: pending)
        var record = context; record["app_id"] = appID; record["capture_id"] = id; record["saved_requested_settings"] = savedSettings(appID)
        record["state"] = "launch_armed; native pair manifests decide actual capture"; record["input_stage"] = "final guest swapchain colour before FG"
        try? json(record, to: dir.appendingPathComponent("host-session.json")); activeID = id
        return dir.appendingPathComponent("frames").path
    }
    static func cancelPending() {
        try? FileManager.default.removeItem(at: pending)
        _ = tl_vk_framegen_capture_arm(nil, 0, 0, 0)
        if let dir = latestFolder, let data = try? Data(contentsOf: dir.appendingPathComponent("host-session.json")),
           var record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            record["state"] = "cancelled"; try? json(record, to: dir.appendingPathComponent("host-session.json"))
        }
    }
    static var conciseStatus: String {
        guard let dir = latestFolder else { return "Off" }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("frames/pair-01.json")),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let data = try? Data(contentsOf: dir.appendingPathComponent("host-session.json")),
               let host = try? JSONSerialization.jsonObject(with: data) as? [String: Any], host["state"] as? String == "cancelled" { return "Cancelled" }
            return "Waiting"
        }
        return record["state"] as? String == "complete" ? "Saved" : "Incomplete"
    }
    static var status: String {
        guard let dir = latestFolder else { return "No frame evidence saved. Capture stays off unless explicitly armed." }
        let file = dir.appendingPathComponent("frames/pair-01.json")
        guard let data = try? Data(contentsOf: file), let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Capture queued or waiting for rendered frames. A missing pair is not a successful capture."
        }
        if result["state"] as? String == "complete" {
            return result["reconstruction_quality"] as? [String: Any] != nil
                ? "Matched images, staged flow and GPU quality decision saved locally. Share the diagnostic bundle when ready."
                : "Older matched images and final flow saved; GPU quality decision unavailable in that capture. Build identity is in the bundle."
        }
        return "Capture incomplete: \(result["error"] ?? "reason unavailable"). Logs can still be shared."
    }
    static func exportContext(appID: String? = nil) throws -> (URL?, [URL], Data, URL) {
        let fm = FileManager.default
        let out = root.appendingPathComponent("Exports", isDirectory: true); try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let document = HuskLog.logFileURL.deletingLastPathComponent()
        let logs = [HuskLog.logFileURL, HuskLog.nativeLogURL, document.appendingPathComponent("husk-prev.log"), HuskLog.previousNativeLogURL]
        var export = context
        if let appID {
            export["app_id"] = appID; export["saved_requested_settings_at_export"] = savedSettings(appID)
            if let launch = lastLaunch, launch.appID == appID { export["effective_launch"] = launch.values }
        }
        var stats = tl_fg_stats()
        if tl_vk_framegen_snapshot(&stats) {
            let snapshot: [String: Any] = ["active": stats.active, "failed": stats.failed,
                "rendered": stats.rendered, "generated_slots": stats.generated, "presented_real": stats.presented_real,
                "dropped": stats.dropped, "resets": stats.resets, "gpu_errors": stats.gpu_errors]
            export["framegen_runtime_snapshot"] = snapshot
            export["counter_scope"] = "Process/driver counters at export, not per-pair counts or proof of unique generated images"
        }
        var capture = latestFolder
        if let appID, let dir = capture {
            let data = try? Data(contentsOf: dir.appendingPathComponent("host-session.json"))
            let host = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if host?["app_id"] as? String != appID { capture = nil; export["capture_omission"] = "Latest capture belongs to another app" }
        }
        let contextData = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
        let name = "Husk-Diagnostics-" + String(HuskLog.sessionID.prefix(8)) + "-" + String(UUID().uuidString.prefix(8)) + ".zip"
        return (capture, logs, contextData, out.appendingPathComponent(name))
    }
    static func pruneExports(keeping output: URL) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: output.deletingLastPathComponent(), includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey])) ?? []
        let old = files.filter { $0 != output && $0.pathExtension == "zip" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for url in old.dropFirst(2) where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true { try? fm.removeItem(at: url) }
    }
    private static func prune(keeping current: String) {
        let root = self.root, protected = Set([current, activeID].compactMap { $0 })
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey]) else { return }
            let old = children.filter { UUID(uuidString: $0.lastPathComponent) != nil && !protected.contains($0.lastPathComponent) }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for url in old.dropFirst() where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true { try? fm.removeItem(at: url) }
        }
    }
}

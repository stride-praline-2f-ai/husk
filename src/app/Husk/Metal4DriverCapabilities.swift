import Foundation

/// Package admission only. Runtime GPU/OS and native configure calls remain
/// required; a manifest does not establish correctness or measured benefit.
struct Metal4DriverCapabilities: Equatable {
    var frameGeneration = false
    var nativeArchives = false
    static let current: Self = {
        guard let root = Bundle.main.privateFrameworksPath else { return .init() }
        let framework = root + "/HuskKosmicKrisp.framework/"
        guard let data = FileManager.default.contents(atPath: framework + "HuskMetal4Build.json"), data.count <= 32_768 else { return .init() }
        return read(data, binaryAvailable: FileManager.default.fileExists(atPath: framework + "HuskKosmicKrisp"))
    }()
    static func read(_ data: Data, binaryAvailable: Bool) -> Self {
        guard binaryAvailable, data.count <= 32_768,
              let value = try? JSONDecoder().decode(Manifest.self, from: data),
              value.schema == 2, value.husk_bridge_abi == 1, value.native_archive_abi == 2,
              value.mesa == "b39d173ca9369c19fda2635be6655d308067e52d",
              value.source == "26620bf5319a0f5a5cca47cfecec797cafe45493" else { return .init() }
        return .init(frameGeneration: value.frame_generation, nativeArchives: true)
    }
    private struct Manifest: Decodable {
        let schema, husk_bridge_abi, native_archive_abi: Int
        let mesa, source: String
        let frame_generation: Bool
    }
}

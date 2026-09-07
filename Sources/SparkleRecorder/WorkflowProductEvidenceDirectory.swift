import Foundation
import SparkleRecorderCore

struct WorkflowProductEvidenceDirectorySnapshot: Equatable, Sendable {
    var existingPaths: Set<String>
    var fileByteCounts: [String: Int64]
    var clipContainers: [String: AutomationProductEvidenceClipContainer]
    var sidecarContents: [String: String]
}

enum WorkflowProductEvidenceDirectory {
    static func snapshot(at directoryURL: URL) throws -> WorkflowProductEvidenceDirectorySnapshot {
        let resolvedDirectoryURL = directoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: resolvedDirectoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return WorkflowProductEvidenceDirectorySnapshot(
                existingPaths: [],
                fileByteCounts: [:],
                clipContainers: [:],
                sidecarContents: [:]
            )
        }

        let existingPaths = Set(
            try FileManager.default.contentsOfDirectory(atPath: resolvedDirectoryURL.path)
        )
        var fileByteCounts: [String: Int64] = [:]
        var clipContainers: [String: AutomationProductEvidenceClipContainer] = [:]
        var sidecarContents: [String: String] = [:]

        for path in existingPaths {
            let url = resolvedDirectoryURL.appendingPathComponent(path, isDirectory: false)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber {
                fileByteCounts[path] = size.int64Value
            }

            if path.hasSuffix(".mov") || path.hasSuffix(".mp4") {
                clipContainers[path] = try clipContainer(at: url)
            }
            if path.hasSuffix(".md") {
                sidecarContents[path] = try String(contentsOf: url, encoding: .utf8)
            }
        }

        return WorkflowProductEvidenceDirectorySnapshot(
            existingPaths: existingPaths,
            fileByteCounts: fileByteCounts,
            clipContainers: clipContainers,
            sidecarContents: sidecarContents
        )
    }

    private static func clipContainer(
        at url: URL
    ) throws -> AutomationProductEvidenceClipContainer {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 64) ?? Data()
        return clipContainer(from: data)
    }

    static func clipContainer(
        from data: Data
    ) -> AutomationProductEvidenceClipContainer {
        let bytes = Array(data)
        guard bytes.count >= 8 else {
            return .unsupported
        }
        let atomType = String(bytes: bytes[4..<8], encoding: .ascii) ?? ""
        if atomType == "ftyp" || ["moov", "mdat", "wide", "free"].contains(atomType) {
            return .isoBaseMedia
        }
        return .unsupported
    }
}

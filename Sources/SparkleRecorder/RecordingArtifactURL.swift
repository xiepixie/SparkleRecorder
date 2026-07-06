import Foundation
import SparkleRecorderCore

extension URL {
    func appendingRecordingArtifactRef(_ ref: RecordingArtifactRef) -> URL {
        ref.path
            .split(separator: "/")
            .map(String.init)
            .reduce(self) { partial, component in
                partial.appendingPathComponent(component)
            }
    }
}

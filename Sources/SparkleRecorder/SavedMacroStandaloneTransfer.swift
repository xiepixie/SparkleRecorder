import Foundation
import SparkleRecorderCore

enum SavedMacroStandaloneTransfer {
  static func importedCopy(
    from payload: SavedMacro,
    id: UUID = UUID()
  ) -> SavedMacro {
    var copy = payload
    copy.id = id
    copy.libraryOrder = nil
    copy.hotkey = nil
    copy.chainTo = nil
    copy.semanticRecording = nil
    copy.refreshCachesFromEvents()
    return copy
  }

  static func exportedPayload(
    from macro: SavedMacro,
    events: [RecordedEvent]
  ) -> SavedMacro {
    var payload = macro
    payload.events = events
    payload.libraryOrder = nil
    payload.chainTo = nil
    payload.semanticRecording = nil
    payload.refreshCachesFromEvents()
    return payload
  }
}

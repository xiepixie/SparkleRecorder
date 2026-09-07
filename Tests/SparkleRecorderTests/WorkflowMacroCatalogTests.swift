import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore
@testable import SparkleRecorderTooling

@Suite("Workflow Macro Catalog Tests")
struct WorkflowMacroCatalogTests {
    @Test("Explicit missing macro directory is an empty catalog")
    func missingDirectoryIsEmptyCatalog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-MacroCatalog-Missing-\(UUID().uuidString)", isDirectory: true)

        let macros = try WorkflowMacroCatalog.load(macrosDirectory: directory)

        #expect(macros.isEmpty)
    }

    @Test("Macro catalog loads package events and sorts newest first")
    func loadsPackageEventsAndSortsNewestFirst() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-MacroCatalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let older = SavedMacro(
            name: "Older",
            events: [],
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = SavedMacro(
            name: "Newer",
            events: [],
            createdAt: Date(timeIntervalSince1970: 200),
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let olderEvents = [TestFixtures.clickEvent(time: 0.25)]
        let newerEvents = TestFixtures.clickPair()

        try writePackage(older, events: olderEvents, root: root)
        try writePackage(newer, events: newerEvents, root: root)

        let macros = try WorkflowMacroCatalog.load(macrosDirectory: root)

        #expect(macros.map(\.name) == ["Newer", "Older"])
        #expect(macros[0].events == newerEvents)
        #expect(macros[0].eventCount == newerEvents.count)
        #expect(macros[1].events == olderEvents)
        #expect(macros[1].eventCount == olderEvents.count)
    }

    private func writePackage(
        _ macro: SavedMacro,
        events: [RecordedEvent],
        root: URL
    ) throws {
        let package = root.appendingPathComponent("\(macro.id.uuidString).sparkrec", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        try encoder.encode(macro).write(to: package.appendingPathComponent("macro.json"), options: .atomic)
        try encoder.encode(events).write(to: package.appendingPathComponent("events.json"), options: .atomic)
    }
}

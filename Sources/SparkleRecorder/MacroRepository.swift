import Foundation
import SparkleRecorderCore
import AppKit

public actor MacroRepository {
    public static let shared = MacroRepository()
    
    private let macrosDirectory: URL
    private let appSupport: URL
    private var didMigrate = false
    
    public init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        self.appSupport = appSupport
        let base = appSupport.appendingPathComponent("SparkleRecorder", isDirectory: true)
        self.macrosDirectory = base.appendingPathComponent("Macros", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: self.macrosDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    private func migrateLegacyJsonToSparkrec() {
        let base = appSupport.appendingPathComponent("SparkleRecorder", isDirectory: true)
        let legacyJSONURL = base.appendingPathComponent("library.json")
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: legacyJSONURL.path) else { return }
        
        // Let's decode the old LibraryData manually
        struct LegacyLibraryData: Codable {
            var macros: [SavedMacro]
            var currentMacroID: UUID?
            var version: Int = 3
        }
        
        guard let data = try? Data(contentsOf: legacyJSONURL),
              let decoded = try? JSONDecoder().decode(LegacyLibraryData.self, from: data) else {
            return
        }
        
        NSLog("SparkleRecorder: Migrating \(decoded.macros.count) macros from library.json to .sparkrec bundles...")
        
        for macro in decoded.macros {
            try? saveMetadata(macro)
            try? saveEvents(macro.events, for: macro.id)
        }
        
        // Archive the old file
        let backupURL = base.appendingPathComponent("library_backup_v3.json")
        try? fm.moveItem(at: legacyJSONURL, to: backupURL)
        
        if let current = decoded.currentMacroID {
            UserDefaults.standard.set(current.uuidString, forKey: "currentMacroID")
        }
        
        NSLog("SparkleRecorder: Migration complete.")
    }
    
    /// Loads all macro manifests from the .sparkrec packages. The `events` array will be empty.
    public func loadAllManifests() throws -> [SavedMacro] {
        if !didMigrate {
            migrateLegacyJsonToSparkrec()
            didMigrate = true
        }
        
        var macros: [SavedMacro] = []
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: macrosDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        
        let decoder = JSONDecoder()
        
        for url in contents {
            if url.pathExtension == "sparkrec" {
                let manifestURL = url.appendingPathComponent("macro.json")
                if let data = try? Data(contentsOf: manifestURL) {
                    if var macro = try? decoder.decode(SavedMacro.self, from: data) {
                        if macro.needsPreviewCacheRefresh,
                           let events = try? loadEvents(for: macro.id) {
                            macro.events = events
                            macro.refreshCachesFromEvents()
                            try? saveMetadata(macro)
                            macro.events = []
                        }
                        macros.append(macro)
                    }
                }
            }
        }
        
        // Sort by creation date descending
        return macros.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Loads the heavy events array for a specific macro.
    public func loadEvents(for id: UUID) throws -> [RecordedEvent] {
        let packageURL = macrosDirectory.appendingPathComponent("\(id.uuidString).sparkrec")
        let eventsURL = packageURL.appendingPathComponent("events.json")
        let data = try Data(contentsOf: eventsURL)
        let decoder = JSONDecoder()
        return try decoder.decode([RecordedEvent].self, from: data)
    }
    
    /// Saves the lightweight metadata (macro.json) for a macro.
    public func saveMetadata(_ macro: SavedMacro) throws {
        let packageURL = macrosDirectory.appendingPathComponent("\(macro.id.uuidString).sparkrec")
        let fm = FileManager.default
        if !fm.fileExists(atPath: packageURL.path) {
            try fm.createDirectory(at: packageURL, withIntermediateDirectories: true, attributes: nil)
            try fm.createDirectory(at: packageURL.appendingPathComponent("assets"), withIntermediateDirectories: true, attributes: nil)
            try fm.createDirectory(at: packageURL.appendingPathComponent("runs"), withIntermediateDirectories: true, attributes: nil)
        }
        
        var manifest = macro
        if !manifest.events.isEmpty {
            manifest.refreshCachesFromEvents()
        } else {
            manifest.cachedDuration = macro.duration
            manifest.cachedEventCount = macro.eventCount
        }
        manifest.events = [] // Clear out events so macro.json is lightweight!
        
        let manifestURL = packageURL.appendingPathComponent("macro.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)
    }
    
    /// Saves the heavy events array (events.json) for a macro.
    public func saveEvents(_ events: [RecordedEvent], for id: UUID) throws {
        let packageURL = macrosDirectory.appendingPathComponent("\(id.uuidString).sparkrec")
        let fm = FileManager.default
        if !fm.fileExists(atPath: packageURL.path) {
            try fm.createDirectory(at: packageURL, withIntermediateDirectories: true, attributes: nil)
            try fm.createDirectory(at: packageURL.appendingPathComponent("assets"), withIntermediateDirectories: true, attributes: nil)
            try fm.createDirectory(at: packageURL.appendingPathComponent("runs"), withIntermediateDirectories: true, attributes: nil)
        }
        let eventsURL = packageURL.appendingPathComponent("events.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let eventsData = try encoder.encode(events)
        try eventsData.write(to: eventsURL, options: .atomic)
    }
    
    public func deleteMacro(id: UUID) throws {
        let packageURL = macrosDirectory.appendingPathComponent("\(id.uuidString).sparkrec")
        try FileManager.default.removeItem(at: packageURL)
    }
    
    /// Get the package URL for a macro
    public nonisolated func packageURL(for id: UUID) -> URL {
        return macrosDirectory.appendingPathComponent("\(id.uuidString).sparkrec")
    }
    
    /// Saves a run evidence report and an optional failure screenshot to the runs directory.
    public func saveRunEvidence(id: UUID, report: RunReport, screenshot: Data?) throws {
        let packageURL = macrosDirectory.appendingPathComponent("\(id.uuidString).sparkrec")
        let runsURL = packageURL.appendingPathComponent("runs")
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: runsURL.path) {
            try fm.createDirectory(at: runsURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        let reportURL = runsURL.appendingPathComponent("latest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let reportData = try encoder.encode(report)
        try reportData.write(to: reportURL, options: .atomic)
        
        let screenshotURL = runsURL.appendingPathComponent("failure.png")
        if let screenshot = screenshot {
            try screenshot.write(to: screenshotURL, options: .atomic)
        } else if fm.fileExists(atPath: screenshotURL.path) {
            try fm.removeItem(at: screenshotURL)
        }
    }
}

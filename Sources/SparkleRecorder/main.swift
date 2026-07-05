import Cocoa
import SparkleRecorderCore

// CLI playback mode: ./SparkleRecorder --play /path/to/macro.tinyrec
// Used by exported .command scripts. Exempt from the single-instance guard —
// it never touches the library.
let args = CommandLine.arguments

if args.count >= 2, args[1] == "--self-test" {
    print("→ Running SparkleRecorder self-test...")
    // 1. TextMacroFormat round-trip
    let events = [
        RecordedEvent.make(.mouseMoved, time: 0.0, x: 100, y: 200),
        RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 200, mouseButton: 0, clickCount: 1),
        RecordedEvent.make(.leftMouseUp, time: 0.2, x: 100, y: 200, mouseButton: 0, clickCount: 1)
    ]
    let text = TextMacroFormat.export(events)
    do {
        let parsed = try TextMacroFormat.parse(text)
        if parsed.events.count != events.count {
            print("❌ Self-test failed: TextMacroFormat round-trip mismatch count")
            exit(1)
        }
    } catch {
        print("❌ Self-test failed: TextMacroFormat parse error \(error)")
        exit(1)
    }
    
    // 2. PointResolver offset
    let resolver = PointResolver()
    let surface = PlaybackSurface(recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600))
    let currentFrame = RectValue(x: 200, y: 150, width: 800, height: 600)
    let ctx = PlaybackContext(surfaces: ["surface-1": surface], currentSurfaceFrames: ["surface-1": currentFrame], coordinateMode: .boundWindowOffset)
    let resolvedResult = resolver.resolve(events[0], context: ctx)
    guard case .success(let resolved) = resolvedResult else {
        print("❌ Self-test failed: PointResolver offset calculation failed")
        exit(1)
    }
    if resolved.x != 200 || resolved.y != 250 {
        print("❌ Self-test failed: PointResolver offset calculation wrong (\(resolved.x),\(resolved.y))")
        exit(1)
    }
    
    // 3. EventGrouper verification
    let grouper = EventGrouper()
    let clickEvents = [
        RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 100),
        RecordedEvent.make(.leftMouseUp, time: 0.2, x: 100, y: 100)
    ]
    let clickGroups = grouper.group(clickEvents)
    if clickGroups.count != 1 || clickGroups[0].kind != .click {
        print("❌ Self-test failed: EventGrouper click grouping wrong")
        exit(1)
    }

    // 4. Strict Keyboard Continuity self-test
    let kbEvents = [
        RecordedEvent.make(.keyDown, time: 0.1, keyCode: 49, flags: 0),
        RecordedEvent.make(.leftMouseDown, time: 0.2, x: 100, y: 100),
        RecordedEvent.make(.leftMouseUp, time: 0.3, x: 100, y: 100),
        RecordedEvent.make(.keyUp, time: 0.4, keyCode: 49, flags: 0)
    ]
    let kbGroups = grouper.group(kbEvents)
    if kbGroups.count != 3 || kbGroups[0].kind != .keyPress || kbGroups[1].kind != .click || kbGroups[2].kind != .keyPress {
        print("❌ Self-test failed: EventGrouper keyboard continuity / interruption logic wrong")
        exit(1)
    }

    // 5. LongPress and KeyHold duration check
    let lpEvents = [
        RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 100),
        RecordedEvent.make(.leftMouseUp, time: 0.5, x: 100, y: 100) // 0.4s > 0.35s
    ]
    let lpGroups = grouper.group(lpEvents)
    if lpGroups.count != 1 || lpGroups[0].kind != .longPress {
        print("❌ Self-test failed: EventGrouper longPress grouping wrong")
        exit(1)
    }

    let khEvents = [
        RecordedEvent.make(.keyDown, time: 0.1, keyCode: 49, flags: 0),
        RecordedEvent.make(.keyUp, time: 0.5, keyCode: 49, flags: 0) // 0.4s > 0.35s
    ]
    let khGroups = grouper.group(khEvents)
    if khGroups.count != 1 || khGroups[0].kind != .keyHold {
        print("❌ Self-test failed: EventGrouper keyHold grouping wrong")
        exit(1)
    }

    // 6. Scroll direction compatibility check
    let scrollEvents = [
        RecordedEvent.make(.scrollWheel, time: 0.1, scrollDeltaY: -5, scrollDeltaX: 0),
        RecordedEvent.make(.scrollWheel, time: 0.2, scrollDeltaY: -4, scrollDeltaX: 0),
        RecordedEvent.make(.scrollWheel, time: 0.3, scrollDeltaY: 3, scrollDeltaX: 0) // reversed
    ]
    let scrollGroups = grouper.group(scrollEvents)
    if scrollGroups.count != 2 || scrollGroups[0].eventIndices.count != 2 || scrollGroups[1].eventIndices.count != 1 {
        print("❌ Self-test failed: EventGrouper scroll direction compatibility wrong")
        exit(1)
    }
    
    // 7. Semantic click/keyboard grouping
    var repeatedClickEvents: [RecordedEvent] = []
    for i in 0..<5 {
        let t = Double(i) * 0.12
        repeatedClickEvents.append(.make(.leftMouseDown, time: t, x: 100, y: 100, mouseButton: 0, clickCount: 1))
        repeatedClickEvents.append(.make(.leftMouseUp, time: t + 0.04, x: 100, y: 100, mouseButton: 0, clickCount: 1))
    }
    let repeatedClickGroups = grouper.group(repeatedClickEvents)
    if repeatedClickGroups.count != 1 || repeatedClickGroups[0].kind != .repeatedClick || repeatedClickGroups[0].clickCount != 5 {
        print("❌ Self-test failed: repeated click grouping wrong")
        exit(1)
    }
    
    let shortcutEvents = [
        RecordedEvent.make(.flagsChanged, time: 0.00, keyCode: 55, flags: ModFlag.command),
        RecordedEvent.make(.keyDown, time: 0.02, keyCode: 1, flags: ModFlag.command),
        RecordedEvent.make(.keyUp, time: 0.04, keyCode: 1, flags: ModFlag.command),
        RecordedEvent.make(.flagsChanged, time: 0.06, keyCode: 55, flags: 0)
    ]
    let shortcutGroups = grouper.group(shortcutEvents)
    if shortcutGroups.count != 1 || shortcutGroups[0].kind != .shortcut || !shortcutGroups[0].summary.contains("Cmd+S") {
        print("❌ Self-test failed: shortcut grouping wrong")
        exit(1)
    }
    
    var h = RecordedEvent.make(.keyDown, time: 0.10, keyCode: 4)
    h.unicodeString = "h"
    let hUp = RecordedEvent.make(.keyUp, time: 0.12, keyCode: 4)
    var i = RecordedEvent.make(.keyDown, time: 0.20, keyCode: 34)
    i.unicodeString = "i"
    let iUp = RecordedEvent.make(.keyUp, time: 0.22, keyCode: 34)
    let textGroups = grouper.group([h, hUp, i, iUp])
    if textGroups.count != 1 || textGroups[0].kind != .textInput || textGroups[0].unicodeString != "hi" {
        print("❌ Self-test failed: text input grouping wrong")
        exit(1)
    }
    
    // 8. Content coordinate priority and bounds
    var contentEvent = RecordedEvent.make(.leftMouseDown, time: 0, x: 500, y: 400, mouseButton: 0)
    contentEvent.coordinateBinding = .targetWindow
    contentEvent.surfaceId = "main"
    contentEvent.contentNormalizedX = 0.25
    contentEvent.contentNormalizedY = 0.5
    contentEvent.contentLocalX = 10
    contentEvent.contentLocalY = 10
    let contentSurface = PlaybackSurface(
        recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600),
        recordedContentFrame: RectValue(x: 100, y: 128, width: 800, height: 572)
    )
    let contentContext = PlaybackContext(
        surfaces: ["main": contentSurface],
        currentSurfaceFrames: ["main": RectValue(x: 300, y: 200, width: 900, height: 700)],
        currentContentFrames: ["main": RectValue(x: 300, y: 235, width: 900, height: 665)]
    )
    guard case .success(let contentPoint) = resolver.resolve(contentEvent, context: contentContext),
          abs(contentPoint.x - 525) < 0.001,
          abs(contentPoint.y - 567.5) < 0.001 else {
        print("❌ Self-test failed: content coordinate priority wrong")
        exit(1)
    }
    contentEvent.contentNormalizedX = 1.2
    guard case .failure(.resolvedPointOutOfBounds(_, _)) = resolver.resolve(contentEvent, context: contentContext) else {
        print("❌ Self-test failed: content coordinate bounds check wrong")
        exit(1)
    }
    
    // 9. Full scroll payload aggregation
    var firstScroll = RecordedEvent.make(.scrollWheel, time: 0.1, x: 200, y: 200, scrollDeltaY: -5, scrollDeltaX: 1)
    firstScroll.scrollPayload = ScrollPayload(deltaX: 1, deltaY: -5, lineDeltaX: 0, lineDeltaY: -1, phase: 1, momentumPhase: 0, fixedDeltaX: 0.5, fixedDeltaY: -1.5, isContinuous: true)
    var secondScroll = RecordedEvent.make(.scrollWheel, time: 0.2, x: 202, y: 202, scrollDeltaY: -4, scrollDeltaX: 2)
    secondScroll.scrollPayload = ScrollPayload(deltaX: 2, deltaY: -4, lineDeltaX: 1, lineDeltaY: -1, phase: 2, momentumPhase: 3, fixedDeltaX: 1.0, fixedDeltaY: -2.0, isContinuous: false)
    let payloadGroups = grouper.group([firstScroll, secondScroll])
    if payloadGroups.count != 1 ||
        payloadGroups[0].scrollPayload?.deltaX != 3 ||
        payloadGroups[0].scrollPayload?.deltaY != -9 ||
        payloadGroups[0].scrollPayload?.lineDeltaY != -2 ||
        payloadGroups[0].scrollPayload?.momentumPhase != 3 ||
        payloadGroups[0].scrollPayload?.fixedDeltaY != -3.5 ||
        payloadGroups[0].scrollPayload?.isContinuous != true {
        print("❌ Self-test failed: scroll payload aggregation wrong")
        exit(1)
    }
    
    print("✅ Self-test completed successfully!")
    exit(0)
}

if args.count >= 3, args[1] == "--play" {
    let path = args[2]
    let url = URL(fileURLWithPath: path)
    do {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        let events: [RecordedEvent]
        let speed: Double
        let loops: Int
        var context = PlaybackContext()
        var targetID: UUID? = nil
        if let saved = try? dec.decode(SavedMacro.self, from: data), !saved.events.isEmpty {
            events = saved.events
            speed = saved.speed
            // Continuous (0) would run forever with no in-app stop hotkey — clamp.
            loops = max(1, saved.loops)
            targetID = saved.id
            
            if !saved.surfaces.isEmpty {
                // Activate target apps immediately so they can be ready.
                // The actual window frames will be lazily resolved by WindowTracker.
                let bundleIDs = Set(saved.surfaces.values.compactMap { $0.bundleIdentifier })
                for bid in bundleIDs {
                    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                    if let app = apps.first {
                        if #available(macOS 14.0, *) {
                            app.activate()
                        } else {
                            app.activate(options: [.activateIgnoringOtherApps])
                        }
                    } else {
                        FileHandle.standardError.write(Data("SparkleRecorder: Warning: A target app is not running.\n".utf8))
                    }
                }
                
                context = PlaybackContext(
                    surfaces: saved.surfaces,
                    currentSurfaceFrames: [:],
                    coordinateMode: saved.followWindowOffset ? .boundWindowOffset : .screenAbsolute
                )
            }
        } else {
            let macro = try dec.decode(Macro.self, from: data)
            events = macro.events
            speed = 1.0
            loops = 1
        }

        // Post events from a background thread with plain sleeps — no run-loop
        // pumping, no MainActor hops, so timing stays faithful to the recording.
        let semaphore = DispatchSemaphore(value: 0)
        let playbackEvents = events
        let playbackLoops = loops
        let playbackSpeed = speed
        let playbackContext = context
        let playbackTargetID = targetID
        Thread.detachNewThread {
            Player.playSynchronously(
                macroID: playbackTargetID,
                events: playbackEvents,
                loops: playbackLoops,
                speed: playbackSpeed,
                context: playbackContext,
                windowTracker: WindowTracker()
            )
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("SparkleRecorder: failed to play \(path): \(error)\n".utf8))
        exit(1)
    }
}

// CLI conversion mode: ./SparkleRecorder --convert in.rec out.tinyrec
// Converts legacy Windows .rec or text .txt/.trm to .tinyrec (JSON) or .txt (TRM),
// chosen by the OUTPUT extension. No GUI, exempt from the single-instance guard.
if args.count >= 4, args[1] == "--convert" {
    let inURL = URL(fileURLWithPath: args[2])
    let outURL = URL(fileURLWithPath: args[3])
    do {
        let data = try Data(contentsOf: inURL)
        let inExt = inURL.pathExtension.lowercased()
        let result: MacroImportResult
        switch inExt {
        case "rec":
            result = try LegacyRecImporter.parse(data)
        case "txt", "trm":
            guard let text = String(data: data, encoding: .utf8) else {
                throw MacroImportError.notTextFormat("input is not UTF-8 text.")
            }
            result = try TextMacroFormat.parse(text)
        case "tinyrec", "json":
            let dec = JSONDecoder()
            if let saved = try? dec.decode(SavedMacro.self, from: data) {
                result = MacroImportResult(events: saved.events, parsed: saved.events.count, skipped: 0, warning: nil)
            } else {
                let macro = try dec.decode(Macro.self, from: data)
                result = MacroImportResult(events: macro.events, parsed: macro.events.count, skipped: 0, warning: nil)
            }
        default:
            // Sniff.
            if data.count % 20 == 0, let r = try? LegacyRecImporter.parse(data) {
                result = r
            } else if let text = String(data: data, encoding: .utf8), let r = try? TextMacroFormat.parse(text) {
                result = r
            } else {
                throw MacroImportError.unreadable("unrecognized input format.")
            }
        }

        let outExt = outURL.pathExtension.lowercased()
        let name = inURL.deletingPathExtension().lastPathComponent
        if outExt == "txt" || outExt == "trm" {
            try TextMacroFormat.export(result.events).write(to: outURL, atomically: true, encoding: .utf8)
        } else {
            let macro = SavedMacro(name: name, events: result.events)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            try enc.encode(macro).write(to: outURL)
        }

        var msg = "SparkleRecorder: converted \(result.events.count) events -> \(outURL.lastPathComponent)"
        if result.skipped > 0 { msg += " (\(result.skipped) skipped)" }
        if let w = result.warning { msg += "\n  warning: \(w)" }
        FileHandle.standardOutput.write(Data((msg + "\n").utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("SparkleRecorder: conversion failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

// Single-instance guard: a second copy would double-register Carbon hotkeys,
// run a second event tap, and clobber library.json last-writer-wins.
let myPID = ProcessInfo.processInfo.processIdentifier
let twin = NSWorkspace.shared.runningApplications.first { app in
    app.processIdentifier != myPID &&
    (app.bundleIdentifier == "com.sparklerecorder.app" ||
     app.executableURL?.lastPathComponent == "SparkleRecorder")
}
if let twin {
    twin.activate()
    exit(0)
}

// Normal app mode — full Dock app.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

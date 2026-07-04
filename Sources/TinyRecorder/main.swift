import Cocoa
import TinyRecorderCore

// CLI playback mode: ./TinyRecorder --play /path/to/macro.tinyrec
// Used by exported .command scripts. Exempt from the single-instance guard —
// it never touches the library.
let args = CommandLine.arguments

if args.count >= 2, args[1] == "--self-test" {
    print("→ Running TinyRecorder self-test...")
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
    let ctx = PlaybackContext(surface: surface, currentSurfaceFrame: currentFrame, coordinateMode: .boundWindowOffset)
    let resolved = resolver.resolve(events[0], context: ctx)
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
        if let saved = try? dec.decode(SavedMacro.self, from: data), !saved.events.isEmpty {
            events = saved.events
            speed = saved.speed
            // Continuous (0) would run forever with no in-app stop hotkey — clamp.
            loops = max(1, saved.loops)
            
            if let surface = saved.surface {
                if let bid = surface.bundleIdentifier {
                    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                    if let app = apps.first {
                        if #available(macOS 14.0, *) {
                            app.activate()
                        } else {
                            app.activate(options: [.activateIgnoringOtherApps])
                        }
                    } else {
                        FileHandle.standardError.write(Data("TinyRecorder: Target app '\(surface.appName ?? "App")' is not running. Aborting CLI playback.\n".utf8))
                        exit(1)
                    }
                }
                
                // Poll frontmost app and focused window every 50ms up to 1.5s
                var capturedContext: PlaybackContext? = nil
                let startTime = CFAbsoluteTimeGetCurrent()
                let capture = WindowSurfaceCapture()
                
                while CFAbsoluteTimeGetCurrent() - startTime < 1.5 {
                    if let currentSurface = try? capture.captureFrontmostWindow(),
                       currentSurface.bundleIdentifier == surface.bundleIdentifier {
                        let currentFrame = currentSurface.recordedFrame
                        let rec = surface.recordedFrame
                        let dw = abs(rec.width - currentFrame.width)
                        let dh = abs(rec.height - currentFrame.height)
                        
                        if dw > 50 || dh > 50 {
                            FileHandle.standardError.write(Data("TinyRecorder: Severe window size mismatch. Recorded: \(Int(rec.width))x\(Int(rec.height)), Current: \(Int(currentFrame.width))x\(Int(currentFrame.height)). Aborting CLI playback.\n".utf8))
                            exit(1)
                        } else if dw > 10 || dh > 10 {
                            FileHandle.standardOutput.write(Data("TinyRecorder: Warning: Minor window size difference (offset may be inaccurate).\n".utf8))
                        }
                        
                        if let recTitle = surface.windowTitle, let curTitle = currentSurface.windowTitle, recTitle != curTitle {
                            FileHandle.standardError.write(Data("TinyRecorder: Window title mismatch. Expected '\(recTitle)', Current: '\(curTitle)'. Aborting CLI playback.\n".utf8))
                            exit(1)
                        }
                        
                        capturedContext = PlaybackContext(
                            surface: surface,
                            currentSurfaceFrame: currentFrame,
                            coordinateMode: saved.followWindowOffset ? .boundWindowOffset : .screenAbsolute
                        )
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                }
                
                if let ctx = capturedContext {
                    context = ctx
                } else {
                    FileHandle.standardError.write(Data("TinyRecorder: Failed to capture target window focus. Aborting CLI playback.\n".utf8))
                    exit(1)
                }
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
        Thread.detachNewThread {
            Player.playSynchronously(events: events, loops: loops, speed: speed, context: context)
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("TinyRecorder: failed to play \(path): \(error)\n".utf8))
        exit(1)
    }
}

// CLI conversion mode: ./TinyRecorder --convert in.rec out.tinyrec
// Converts TinyTask .rec or text .txt/.trm to .tinyrec (JSON) or .txt (TRM),
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
            result = try TinyTaskImporter.parse(data)
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
            if data.count % 20 == 0, let r = try? TinyTaskImporter.parse(data) {
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

        var msg = "TinyRecorder: converted \(result.events.count) events -> \(outURL.lastPathComponent)"
        if result.skipped > 0 { msg += " (\(result.skipped) skipped)" }
        if let w = result.warning { msg += "\n  warning: \(w)" }
        FileHandle.standardOutput.write(Data((msg + "\n").utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("TinyRecorder: conversion failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

// Single-instance guard: a second copy would double-register Carbon hotkeys,
// run a second event tap, and clobber library.json last-writer-wins.
let myPID = ProcessInfo.processInfo.processIdentifier
let twin = NSWorkspace.shared.runningApplications.first { app in
    app.processIdentifier != myPID &&
    (app.bundleIdentifier == "com.tinyrecorder.app" ||
     app.executableURL?.lastPathComponent == "TinyRecorder")
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

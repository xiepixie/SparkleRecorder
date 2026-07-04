import Testing
import Foundation
import CoreGraphics
import TinyRecorderCore

@Suite("TinyRecorder Tests")
struct TinyRecorderTests {
    
    @Test("Text Macro Format Roundtrip")
    func textMacroFormatRoundTrip() {
        let events = [
            RecordedEvent.make(.mouseMoved, time: 0.0, x: 100, y: 200),
            RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 200, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.2, x: 100, y: 200, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.scrollWheel, time: 0.3, scrollDeltaY: -5, scrollDeltaX: 0),
            RecordedEvent.make(.keyDown, time: 0.4, keyCode: 49, flags: 0),
            RecordedEvent.make(.keyUp, time: 0.5, keyCode: 49, flags: 0)
        ]
        
        let exportedText = TextMacroFormat.export(events)
        #expect(exportedText.contains("TINYRECORDER 1"))
        
        do {
            let result = try TextMacroFormat.parse(exportedText)
            #expect(result.events.count == events.count)
            #expect(result.events[0].kind == .mouseMoved)
            #expect(result.events[1].kind == .leftMouseDown)
            #expect(result.events[2].kind == .leftMouseUp)
            #expect(result.events[3].kind == .scrollWheel)
            #expect(result.events[4].kind == .keyDown)
            #expect(result.events[5].kind == .keyUp)
        } catch {
            Issue.record("Failed to parse exported text: \(error)")
        }
    }
    
    @Test("TinyTask Importer Parse Empty")
    func tinyTaskImporterParseEmpty() {
        #expect(throws: Error.self) {
            try TinyTaskImporter.parse(Data())
        }
    }
    
    @Test("Saved Macro Decoding Compatibility")
    func savedMacroDecodingCompatibility() {
        let jsonStr = """
        {
          "id": "A4E7F912-88B9-4DF5-91E3-E3CCF9B3C2D1",
          "name": "Test Macro",
          "events": [
            {
              "kind": 1,
              "time": 0.54,
              "x": 420.5,
              "y": 310.2,
              "keyCode": 0,
              "flags": 0,
              "mouseButton": 0,
              "clickCount": 1,
              "scrollDeltaY": 0,
              "scrollDeltaX": 0
            }
          ],
          "createdAt": 766094400,
          "modifiedAt": 766094412,
          "version": 3,
          "loops": 1,
          "speed": 1.5
        }
        """
        
        guard let data = jsonStr.data(using: .utf8) else {
            Issue.record("Failed to encode mock string")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let macro = try decoder.decode(SavedMacro.self, from: data)
            #expect(macro.name == "Test Macro")
            #expect(macro.speed == 1.5)
            #expect(macro.loops == 1)
            #expect(macro.events.count == 1)
            #expect(macro.events[0].kind == .leftMouseDown)
        } catch {
            Issue.record("SavedMacro failed to decode compatibility JSON: \(error)")
        }
    }
    
    @Test("Synthesizer Dry Run")
    func synthesizerDryRun() {
        class MockPoster: EventPosting {
            var posted: [(RecordedEvent, CGPoint)] = []
            func post(_ event: RecordedEvent, at point: CGPoint) {
                posted.append((event, point))
            }
        }
        
        let poster = MockPoster()
        let synth = MouseKeyboardSynthesizer(poster: poster)
        
        let ev = RecordedEvent.make(.leftMouseDown, time: 0.1, x: 50, y: 60)
        synth.synthesize(ev, at: CGPoint(x: 500, y: 600))
        
        #expect(poster.posted.count == 1)
        #expect(poster.posted[0].0.kind == .leftMouseDown)
        #expect(poster.posted[0].1.x == 500)
        #expect(poster.posted[0].1.y == 600)
    }
    
    @Test("Point Resolver")
    func pointResolver() {
        let resolver = PointResolver()
        let event = RecordedEvent.make(.mouseMoved, time: 0.1, x: 150, y: 250)
        
        // 1. screenAbsolute Mode
        let contextAbsolute = PlaybackContext(coordinateMode: .screenAbsolute)
        let pointAbsolute = resolver.resolve(event, context: contextAbsolute)
        #expect(pointAbsolute.x == 150)
        #expect(pointAbsolute.y == 250)
        
        // 2. boundWindowOffset Mode
        let surface = PlaybackSurface(recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600))
        let currentFrame = RectValue(x: 250, y: 150, width: 800, height: 600)
        
        let contextOffset = PlaybackContext(
            surface: surface,
            currentSurfaceFrame: currentFrame,
            coordinateMode: .boundWindowOffset
        )
        
        let pointOffset = resolver.resolve(event, context: contextOffset)
        #expect(pointOffset.x == 300)
        #expect(pointOffset.y == 300)
    }
    
    @Test("Event Grouper Click and Drag")
    func eventGrouperClickAndDrag() {
        let grouper = EventGrouper()
        
        // 1. Click events
        let clickEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 100),
            RecordedEvent.make(.leftMouseUp, time: 0.2, x: 100, y: 100)
        ]
        let clickGroups = grouper.group(clickEvents)
        #expect(clickGroups.count == 1)
        #expect(clickGroups[0].kind == .click)
        #expect(clickGroups[0].eventIndices == [0, 1])
        #expect(clickGroups[0].startPoint == CGPoint(x: 100, y: 100))
        
        // 2. Drag events
        let dragEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 100),
            RecordedEvent.make(.leftMouseDragged, time: 0.2, x: 105, y: 105),
            RecordedEvent.make(.leftMouseDragged, time: 0.3, x: 110, y: 110),
            RecordedEvent.make(.leftMouseUp, time: 0.4, x: 110, y: 110)
        ]
        let dragGroups = grouper.group(dragEvents)
        #expect(dragGroups.count == 1)
        #expect(dragGroups[0].kind == .drag)
        #expect(dragGroups[0].eventIndices == [0, 1, 2, 3])
        #expect(dragGroups[0].startPoint == CGPoint(x: 100, y: 100))
        #expect(dragGroups[0].endPoint == CGPoint(x: 110, y: 110))
        #expect(dragGroups[0].path.count == 4)
        
        // 3. Wait events (with interval > 200ms)
        let waitEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 100),
            RecordedEvent.make(.leftMouseUp, time: 0.2, x: 100, y: 100),
            // Wait 1.0s gap
            RecordedEvent.make(.scrollWheel, time: 1.2, scrollDeltaY: -5, scrollDeltaX: 0)
        ]
        let waitGroups = grouper.group(waitEvents)
        #expect(waitGroups.count == 3) // Click, Wait, Scroll
        #expect(waitGroups[0].kind == .click)
        #expect(waitGroups[1].kind == .wait)
        #expect(waitGroups[1].startTime == 0.2)
        #expect(waitGroups[1].endTime == 1.2)
        #expect(waitGroups[2].kind == .scroll)
    }

    @Test("Event Grouper Strict Continuity")
    func eventGrouperStrictContinuity() {
        let grouper = EventGrouper()
        let events = [
            RecordedEvent.make(.keyDown, time: 0.1, keyCode: 49, flags: 0),
            RecordedEvent.make(.leftMouseDown, time: 0.2, x: 100, y: 100),
            RecordedEvent.make(.leftMouseUp, time: 0.3, x: 100, y: 100),
            RecordedEvent.make(.keyUp, time: 0.4, keyCode: 49, flags: 0)
        ]
        let groups = grouper.group(events)
        #expect(groups.count == 3)
        #expect(groups[0].kind == .keyPress)
        #expect(groups[1].kind == .click)
        #expect(groups[2].kind == .keyPress)
    }

    @Test("Event Grouper Long Press and Key Hold")
    func eventGrouperLongPressAndKeyHold() {
        let grouper = EventGrouper()
        
        let longPressEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 100),
            RecordedEvent.make(.leftMouseUp, time: 0.5, x: 100, y: 100)
        ]
        let lpGroups = grouper.group(longPressEvents)
        #expect(lpGroups.count == 1)
        #expect(lpGroups[0].kind == .longPress)
        
        let keyHoldEvents = [
            RecordedEvent.make(.keyDown, time: 0.1, keyCode: 49, flags: 0),
            RecordedEvent.make(.keyUp, time: 0.5, keyCode: 49, flags: 0)
        ]
        let khGroups = grouper.group(keyHoldEvents)
        #expect(khGroups.count == 1)
        #expect(khGroups[0].kind == .keyHold)
    }

    @Test("Scroll Direction Compatibility")
    func scrollDirectionCompatibility() {
        let grouper = EventGrouper()
        let scrollEvents = [
            RecordedEvent.make(.scrollWheel, time: 0.1, scrollDeltaY: -5, scrollDeltaX: 0),
            RecordedEvent.make(.scrollWheel, time: 0.2, scrollDeltaY: -4, scrollDeltaX: 0),
            RecordedEvent.make(.scrollWheel, time: 0.3, scrollDeltaY: 3, scrollDeltaX: 0)
        ]
        let scrollGroups = grouper.group(scrollEvents)
        #expect(scrollGroups.count == 2)
        #expect(scrollGroups[0].kind == .scroll)
        #expect(scrollGroups[1].kind == .scroll)
        #expect(scrollGroups[0].eventIndices.count == 2)
        #expect(scrollGroups[1].eventIndices.count == 1)
    }
}

import Testing
import Foundation
import CoreGraphics
import os
@testable import SparkleRecorderCore

@Suite("SparkleRecorder Tests")
struct SparkleRecorderTests {
    
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
        #expect(exportedText.contains("SPARKLERECORDER 1"))
        
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
    
    @Test("SparkleRecorder Importer Parse Empty")
    func legacyRecImporterParseEmpty() {
        #expect(throws: Error.self) {
            try LegacyRecImporter.parse(Data())
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
        let recorder = PostedInputRecorder()
        let client = EventPosterClient { event, point in
            recorder.append(event: event, point: point)
        }

        let ev = RecordedEvent.make(.leftMouseDown, time: 0.1, x: 50, y: 60)
        client.post(ev, CGPoint(x: 500, y: 600))

        let posted = recorder.snapshot()
        #expect(posted.count == 1)
        #expect(posted[0].event.kind == .leftMouseDown)
        #expect(posted[0].point.x == 500)
        #expect(posted[0].point.y == 600)
    }
    
    @Test("Point Resolver")
    func pointResolver() {
        let resolver = PointResolver()
        let event = RecordedEvent.make(.mouseMoved, time: 0.1, x: 150, y: 250)
        
        // 1. screenAbsolute Mode
        let contextAbsolute = PlaybackContext(coordinateMode: .screenAbsolute)
        let pointAbsolute = try! resolver.resolve(event, context: contextAbsolute).get()
        #expect(pointAbsolute.x == 150)
        #expect(pointAbsolute.y == 250)
        
        // 2. boundWindowOffset Mode
        let surface = PlaybackSurface(recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600))
        let currentFrame = RectValue(x: 250, y: 150, width: 800, height: 600)
        
        let contextOffset = PlaybackContext(
            surfaces: ["main": surface],
            currentSurfaceFrames: ["main": currentFrame],
            coordinateMode: .boundWindowOffset
        )
        
        let pointOffset = try! resolver.resolve(event, context: contextOffset).get()
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

    @Test("Event Grouper Rapid Multi Point Click")
    func eventGrouperRapidMultiPointClick() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.00, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.02, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseDown, time: 0.07, x: 150, y: 120, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.09, x: 150, y: 120, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseDown, time: 0.14, x: 210, y: 140, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.16, x: 210, y: 140, mouseButton: 0, clickCount: 1)
        ]

        let groups = EventGrouper().group(events)
        #expect(groups.count == 1)
        #expect(groups[0].kind == .multiPointClick)
        #expect(groups[0].path == [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 150, y: 120),
            CGPoint(x: 210, y: 140)
        ])
        #expect(groups[0].clickCount == 3)
    }

    @Test("Event Grouper Keeps Wait Between Repeated Clicks")
    func eventGrouperKeepsWaitBetweenRepeatedClicks() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.00, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.02, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseDown, time: 0.32, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.34, x: 100, y: 100, mouseButton: 0, clickCount: 1)
        ]

        let groups = EventGrouper().group(events)

        #expect(groups.count == 3)
        #expect(groups[0].kind == .click)
        #expect(groups[1].kind == .wait)
        #expect(abs(groups[1].duration - 0.30) < 0.0001)
        #expect(groups[2].kind == .click)
    }

    @Test("Event Grouper Keeps Wait Between Point Clicks")
    func eventGrouperKeepsWaitBetweenPointClicks() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.00, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.02, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseDown, time: 0.25, x: 180, y: 120, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.27, x: 180, y: 120, mouseButton: 0, clickCount: 1)
        ]

        let groups = EventGrouper().group(events)

        #expect(groups.count == 3)
        #expect(groups[0].kind == .click)
        #expect(groups[1].kind == .wait)
        #expect(groups[2].kind == .click)
    }

    @Test("Event Grouper Keeps Visual Conditions Between Rapid Point Clicks")
    func eventGrouperKeepsVisualConditionsBetweenRapidPointClicks() {
        var wait = RecordedEvent.make(.waitForText, time: 0.05)
        wait.textAnchor = TextAnchor(
            text: "Ready",
            observedFrame: RectValue(x: 90, y: 80, width: 80, height: 24)
        )
        var verify = RecordedEvent.make(.verifyText, time: 0.11)
        verify.textAnchor = TextAnchor(
            text: "Saved",
            observedFrame: RectValue(x: 180, y: 100, width: 70, height: 24)
        )

        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.00, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.02, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            wait,
            RecordedEvent.make(.leftMouseDown, time: 0.07, x: 180, y: 120, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.09, x: 180, y: 120, mouseButton: 0, clickCount: 1),
            verify,
            RecordedEvent.make(.leftMouseDown, time: 0.13, x: 240, y: 140, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.15, x: 240, y: 140, mouseButton: 0, clickCount: 1)
        ]

        let groups = EventGrouper().group(events)

        #expect(groups.map(\.kind) == [.click, .waitForText, .click, .verifyText, .click])
        #expect(!groups.contains { $0.kind == .multiPointClick })
        #expect(groups[1].textTargetReadiness == .ready)
        #expect(groups[3].textTargetReadiness == .ready)
    }

    @Test("Event Grouper Does Not Merge Text Click With Coordinate Clicks")
    func eventGrouperDoesNotMergeTextClickWithCoordinateClicks() throws {
        let anchor = TextAnchor(
            text: "Confirm",
            observedFrame: RectValue(x: 90, y: 90, width: 80, height: 24),
            searchRegion: RectValue(x: 70, y: 70, width: 140, height: 80),
            coordinateFallback: PointValue(x: 130, y: 102)
        )
        var textDown = RecordedEvent.make(.leftMouseDown, time: 0.00, x: 130, y: 102, mouseButton: 0, clickCount: 1)
        textDown.coordinateStrategy = .locatorOnly
        textDown.locatorFallbackPolicy = .fail
        textDown.textAnchor = anchor
        var textUp = RecordedEvent.make(.leftMouseUp, time: 0.02, x: 130, y: 102, mouseButton: 0, clickCount: 1)
        textUp.coordinateStrategy = .locatorOnly
        textUp.locatorFallbackPolicy = .fail
        textUp.textAnchor = anchor

        let events = [
            textDown,
            textUp,
            RecordedEvent.make(.leftMouseDown, time: 0.07, x: 180, y: 120, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.09, x: 180, y: 120, mouseButton: 0, clickCount: 1)
        ]

        let groups = EventGrouper().group(events)

        #expect(groups.count == 2)
        #expect(groups[0].kind == .click)
        #expect(groups[0].textAnchor?.text == "Confirm")
        #expect(groups[1].kind == .click)
        #expect(groups[1].textAnchor == nil)
    }

    @Test("Event Grouper Labels Empty Text Click As Needs Text")
    func eventGrouperLabelsEmptyTextClickAsNeedsText() throws {
        let emptyAnchor = TextAnchor(
            text: "",
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)
        )
        var down = RecordedEvent.make(.leftMouseDown, time: 0.00, x: 130, y: 102, mouseButton: 0, clickCount: 1)
        down.coordinateStrategy = .locatorOnly
        down.textAnchor = emptyAnchor
        var up = RecordedEvent.make(.leftMouseUp, time: 0.02, x: 130, y: 102, mouseButton: 0, clickCount: 1)
        up.coordinateStrategy = .locatorOnly
        up.textAnchor = emptyAnchor

        let group = try #require(EventGrouper().group([down, up]).first)

        #expect(group.kind == .click)
        #expect(group.summary == "Click text (needs text)")
        #expect(group.textAnchor?.text == "")
        #expect(group.textTargetReadiness == .missingText)
    }

    @Test("Event Grouper Labels Locator Click Without Anchor As Needs Text")
    func eventGrouperLabelsLocatorClickWithoutAnchorAsNeedsText() throws {
        var down = RecordedEvent.make(.leftMouseDown, time: 0.00, x: 130, y: 102, mouseButton: 0, clickCount: 1)
        down.coordinateStrategy = .locatorOnly
        var up = RecordedEvent.make(.leftMouseUp, time: 0.02, x: 130, y: 102, mouseButton: 0, clickCount: 1)
        up.coordinateStrategy = .locatorOnly

        let group = try #require(EventGrouper().group([down, up]).first)

        #expect(group.kind == .click)
        #expect(group.summary == "Click text (needs text)")
        #expect(group.textAnchor == nil)
        #expect(group.textTargetReadiness == .missingAnchor)
    }

    @Test("Event Grouper Does Not Merge Incomplete Text Click With Coordinate Clicks")
    func eventGrouperDoesNotMergeIncompleteTextClickWithCoordinateClicks() throws {
        var textDown = RecordedEvent.make(.leftMouseDown, time: 0.00, x: 130, y: 102, mouseButton: 0, clickCount: 1)
        textDown.coordinateStrategy = .locatorOnly
        var textUp = RecordedEvent.make(.leftMouseUp, time: 0.02, x: 130, y: 102, mouseButton: 0, clickCount: 1)
        textUp.coordinateStrategy = .locatorOnly

        let events = [
            textDown,
            textUp,
            RecordedEvent.make(.leftMouseDown, time: 0.07, x: 180, y: 120, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.09, x: 180, y: 120, mouseButton: 0, clickCount: 1)
        ]

        let groups = EventGrouper().group(events)

        #expect(groups.count == 2)
        #expect(groups[0].summary == "Click text (needs text)")
        #expect(groups[0].textTargetReadiness == .missingAnchor)
        #expect(groups[1].kind == .click)
        #expect(groups[1].textTargetReadiness == .notTextTarget)
    }

    @Test("Recorded Coordinate Click Can Become Text Click")
    func recordedCoordinateClickCanBecomeTextClick() throws {
        var events = TestFixtures.clickPair(
            downTime: 0.00,
            upTime: 0.02,
            x: 130,
            y: 102
        )
        let anchor = TextAnchor(
            text: "Confirm",
            observedFrame: RectValue(x: 90, y: 90, width: 80, height: 24),
            searchRegion: RectValue(x: 70, y: 70, width: 140, height: 80),
            coordinateFallback: PointValue(x: 130, y: 102)
        )

        for index in events.indices {
            events[index].coordinateStrategy = .locatorOnly
            events[index].locatorFallbackPolicy = .fail
            events[index].textAnchor = anchor
            events[index].textTimeout = 8.0
        }

        let group = try #require(EventGrouper().group(events).first)

        #expect(group.kind == .click)
        #expect(group.summary == "Click text: Confirm")
        #expect(group.textAnchor?.text == "Confirm")
        #expect(group.textTimeout == 8.0)
        #expect(group.textTargetReadiness == .ready)
        #expect(events.allSatisfy { $0.coordinateStrategy == .locatorOnly })
    }

    @Test("Event Grouper Labels Wait Text Gone")
    func eventGrouperLabelsWaitTextGone() throws {
        var event = RecordedEvent.make(.waitForText, time: 1)
        event.textAnchor = TextAnchor(
            text: "Loading",
            observedFrame: RectValue(x: 0, y: 0, width: 120, height: 24)
        )
        event.textTimeout = 5
        event.verifyMustExist = false

        let group = try #require(EventGrouper().group([event]).first)

        #expect(group.kind == .waitForTextGone)
        #expect(group.summary == "Wait Text Gone: Loading")
        #expect(group.verifyMustExist == false)
    }

    @Test("Event Grouper Labels Empty Wait And Verify Text As Needs Text")
    func eventGrouperLabelsEmptyWaitAndVerifyTextAsNeedsText() {
        let emptyAnchor = TextAnchor(
            text: "   ",
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)
        )
        var wait = RecordedEvent.make(.waitForText, time: 1)
        wait.textAnchor = emptyAnchor
        wait.verifyMustExist = true
        var gone = RecordedEvent.make(.waitForText, time: 2)
        gone.textAnchor = emptyAnchor
        gone.verifyMustExist = false
        var verify = RecordedEvent.make(.verifyText, time: 3)
        verify.textAnchor = emptyAnchor

        let groups = EventGrouper().group([wait, gone, verify])

        #expect(groups.filter { $0.kind != .wait }.map(\.summary) == [
            "Wait Text (needs text)",
            "Wait Text Gone (needs text)",
            "Verify Text (needs text)"
        ])
        #expect(groups.filter { $0.kind != .wait }.map(\.textTargetReadiness) == [
            .missingText,
            .missingText,
            .missingText
        ])
        #expect(groups.filter { $0.kind == .wait }.count == 2)
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

    @Test("Event Grouper Merges Scroll Segment Across Short Pause")
    func eventGrouperMergesScrollSegmentAcrossShortPause() {
        let scrollEvents = [
            RecordedEvent.make(.scrollWheel, time: 3.708, x: 300, y: 240, scrollDeltaY: -12, scrollDeltaX: 0),
            RecordedEvent.make(.scrollWheel, time: 3.724, x: 300, y: 240, scrollDeltaY: -12, scrollDeltaX: 0),
            RecordedEvent.make(.scrollWheel, time: 3.762, x: 301, y: 241, scrollDeltaY: -12, scrollDeltaX: 0),
            RecordedEvent.make(.scrollWheel, time: 4.144, x: 302, y: 242, scrollDeltaY: -12, scrollDeltaX: 0),
            RecordedEvent.make(.scrollWheel, time: 4.169, x: 302, y: 242, scrollDeltaY: -12, scrollDeltaX: 0),
            RecordedEvent.make(.scrollWheel, time: 4.235, x: 303, y: 242, scrollDeltaY: -12, scrollDeltaX: 0)
        ]

        let groups = EventGrouper().group(scrollEvents)
        #expect(groups.count == 1)
        #expect(groups[0].kind == .scroll)
        #expect(groups[0].eventIndices.count == 6)
        #expect(groups[0].scrollDeltaY == -72)
    }

    @Test("Point Resolver Fail-Safe (Out of Bounds)")
    func pointResolverOutOfBounds() {
        let resolver = PointResolver()
        let event = RecordedEvent.make(.mouseMoved, time: 0.1, x: 1500, y: 1500)
        
        let surface = PlaybackSurface(recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600))
        let currentFrame = RectValue(x: 250, y: 150, width: 800, height: 600)
        
        let contextOffset = PlaybackContext(
            surfaces: ["main": surface],
            currentSurfaceFrames: ["main": currentFrame],
            coordinateMode: .boundWindowOffset
        )
        
        let result = resolver.resolve(event, context: contextOffset)
        // Since event is at (1500, 1500) and recordedFrame is 800x600 at (100, 100), 
        // the normalized point will be out of bounds (0...1).
        if case .failure(let error) = result {
            if case .resolvedPointOutOfBounds = error {
                // Success
            } else {
                Issue.record("Expected out of bounds error but got \(error)")
            }
        } else {
            Issue.record("Expected out of bounds error but got success")
        }
    }

    @Test("Event Grouper Scroll Payload Accumulation")
    func eventGrouperScrollPayload() {
        let grouper = EventGrouper()
        var first = RecordedEvent.make(.scrollWheel, time: 0.1, scrollDeltaY: -5, scrollDeltaX: 1)
        first.scrollPayload = ScrollPayload(deltaX: 1, deltaY: -5, lineDeltaX: 0, lineDeltaY: -1, phase: 1, isContinuous: true)
        var second = RecordedEvent.make(.scrollWheel, time: 0.2, scrollDeltaY: -4, scrollDeltaX: 2)
        second.scrollPayload = ScrollPayload(deltaX: 2, deltaY: -4, lineDeltaX: 0, lineDeltaY: -1, phase: 1, isContinuous: true)
        let scrollEvents = [first, second]
        let scrollGroups = grouper.group(scrollEvents)
        #expect(scrollGroups.count == 1)
        #expect(scrollGroups[0].kind == .scroll)
        #expect(scrollGroups[0].scrollPayload?.deltaY == -9)
        #expect(scrollGroups[0].scrollPayload?.deltaX == 3)
    }

    @Test("Event Grouper Unicode Payload")
    func eventGrouperUnicodePayload() {
        let grouper = EventGrouper()
        var eventA = RecordedEvent.make(.keyDown, time: 0.1, keyCode: 0, flags: 0)
        eventA.unicodeString = "a"
        let eventUp = RecordedEvent.make(.keyUp, time: 0.2, keyCode: 0, flags: 0)
        
        let events = [eventA, eventUp]
        let groups = grouper.group(events)
        #expect(groups.count == 1)
        #expect(groups[0].kind == .keyPress)
        #expect(groups[0].unicodeString == "a")
    }

    @Test("RecordedEvent OCR Strategy Encoding and Decoding")
    func recordedEventOCREncodingDecoding() {
        let event = RecordedEvent(
            kind: .leftMouseDown,
            time: 1.0,
            x: 100,
            y: 200,
            keyCode: 0,
            flags: 0,
            mouseButton: 0,
            clickCount: 1,
            scrollDeltaY: 0,
            scrollDeltaX: 0,
            coordinateBinding: .targetWindow,
            coordinateStrategy: .locatorOnly,
            surfaceId: "cookie-run",
            textAnchor: TextAnchor(text: "一次填滿", observedFrame: RectValue(x: 10, y: 10, width: 50, height: 20))
        )
        
        do {
            let data = try JSONEncoder().encode(event)
            let decoded = try JSONDecoder().decode(RecordedEvent.self, from: data)
            #expect(decoded.coordinateBinding == .targetWindow)
            #expect(decoded.coordinateStrategy == .locatorOnly)
            #expect(decoded.surfaceId == "cookie-run")
            #expect(decoded.textAnchor?.text == "一次填滿")
        } catch {
            Issue.record("Failed to round-trip RecordedEvent with OCR values: \(error)")
        }
    }
    
    @Test("Point Resolver Prefers Content Coordinates")
    func pointResolverPrefersContentCoordinates() throws {
        let resolver = PointResolver()
        let surface = PlaybackSurface(
            recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600),
            recordedContentFrame: RectValue(x: 100, y: 128, width: 800, height: 572)
        )
        let context = PlaybackContext(
            surfaces: ["main": surface],
            currentSurfaceFrames: ["main": RectValue(x: 300, y: 200, width: 900, height: 700)],
            currentContentFrames: ["main": RectValue(x: 300, y: 235, width: 900, height: 665)]
        )
        
        var event = RecordedEvent.make(.leftMouseDown, time: 0, x: 500, y: 400, mouseButton: 0)
        event.coordinateBinding = .targetWindow
        event.surfaceId = "main"
        event.contentNormalizedX = 0.25
        event.contentNormalizedY = 0.5
        event.contentLocalX = 10
        event.contentLocalY = 10
        
        let point = try resolver.resolve(event, context: context).get()
        #expect(abs(point.x - 525) < 0.001)
        #expect(abs(point.y - 567.5) < 0.001)
        
        event.contentNormalizedX = 1.2
        if case .failure(.resolvedPointOutOfBounds(_, let bounds)) = resolver.resolve(event, context: context) {
            #expect(abs(bounds.x - 300) < 0.001)
            #expect(abs(bounds.y - 235) < 0.001)
        } else {
            Issue.record("Expected content bounds failure")
        }
    }
    
    @Test("Event Grouper Semantic Actions")
    func eventGrouperSemanticActions() {
        var clickEvents: [RecordedEvent] = []
        for i in 0..<5 {
            let t = Double(i) * 0.12
            clickEvents.append(.make(.leftMouseDown, time: t, x: 100, y: 100, mouseButton: 0, clickCount: 1))
            clickEvents.append(.make(.leftMouseUp, time: t + 0.04, x: 100, y: 100, mouseButton: 0, clickCount: 1))
        }
        let clickGroups = EventGrouper().group(clickEvents)
        #expect(clickGroups.count == 1)
        #expect(clickGroups[0].kind == .repeatedClick)
        #expect(clickGroups[0].clickCount == 5)
        
        let shortcutEvents = [
            RecordedEvent.make(.flagsChanged, time: 0.00, keyCode: 55, flags: ModFlag.command),
            RecordedEvent.make(.keyDown, time: 0.02, keyCode: 1, flags: ModFlag.command),
            RecordedEvent.make(.keyUp, time: 0.04, keyCode: 1, flags: ModFlag.command),
            RecordedEvent.make(.flagsChanged, time: 0.06, keyCode: 55, flags: 0)
        ]
        let shortcutGroups = EventGrouper().group(shortcutEvents)
        #expect(shortcutGroups.count == 1)
        #expect(shortcutGroups[0].kind == .shortcut)
        #expect(shortcutGroups[0].summary.contains("Cmd+S"))
        
        var h = RecordedEvent.make(.keyDown, time: 0.10, keyCode: 4)
        h.unicodeString = "h"
        let hUp = RecordedEvent.make(.keyUp, time: 0.12, keyCode: 4)
        var i = RecordedEvent.make(.keyDown, time: 0.20, keyCode: 34)
        i.unicodeString = "i"
        let iUp = RecordedEvent.make(.keyUp, time: 0.22, keyCode: 34)
        let textGroups = EventGrouper().group([h, hUp, i, iUp])
        #expect(textGroups.count == 1)
        #expect(textGroups[0].kind == .textInput)
        #expect(textGroups[0].unicodeString == "hi")
    }
    
    @Test("Event Grouper Aggregates Full Scroll Payload")
    func eventGrouperAggregatesFullScrollPayload() {
        var first = RecordedEvent.make(.scrollWheel, time: 0.1, x: 200, y: 200, scrollDeltaY: -5, scrollDeltaX: 1)
        first.scrollPayload = ScrollPayload(deltaX: 1, deltaY: -5, lineDeltaX: 0, lineDeltaY: -1, phase: 1, momentumPhase: 0, fixedDeltaX: 0.5, fixedDeltaY: -1.5, isContinuous: true)
        var second = RecordedEvent.make(.scrollWheel, time: 0.2, x: 202, y: 202, scrollDeltaY: -4, scrollDeltaX: 2)
        second.scrollPayload = ScrollPayload(deltaX: 2, deltaY: -4, lineDeltaX: 1, lineDeltaY: -1, phase: 2, momentumPhase: 3, fixedDeltaX: 1.0, fixedDeltaY: -2.0, isContinuous: false)
        
        let groups = EventGrouper().group([first, second])
        #expect(groups.count == 1)
        #expect(groups[0].kind == .scroll)
        #expect(groups[0].scrollPayload?.deltaX == 3)
        #expect(groups[0].scrollPayload?.deltaY == -9)
        #expect(groups[0].scrollPayload?.lineDeltaX == 1)
        #expect(groups[0].scrollPayload?.lineDeltaY == -2)
        #expect(groups[0].scrollPayload?.momentumPhase == 3)
        #expect(groups[0].scrollPayload?.fixedDeltaX == 1.5)
        #expect(groups[0].scrollPayload?.fixedDeltaY == -3.5)
        #expect(groups[0].scrollPayload?.isContinuous == true)
    }

    @Test("Scroll Playback Delta Keeps Recorded Wheel Amount")
    func scrollPlaybackDeltaKeepsRecordedWheelAmount() {
        #expect(RecordedEvent.Kind.scrollWheel.isMouse)
        #expect(PlaybackScrollPlanner.effectivePointDelta(recorded: -12, payload: 0) == -12)
        #expect(PlaybackScrollPlanner.effectivePointDelta(recorded: 18, payload: 0.2) == 18)
        #expect(PlaybackScrollPlanner.effectivePointDelta(recorded: -12, payload: -4.6) == -5)
        #expect(PlaybackScrollPlanner.effectivePointDelta(recorded: 0, payload: 7.0) == 7)
        #expect(PlaybackScrollPlanner.effectiveLineDelta(recorded: -12, payload: nil) == -1)
        #expect(PlaybackScrollPlanner.shouldUseLineScroll(
            payload: ScrollPayload(deltaX: 0, deltaY: 0, lineDeltaX: 0, lineDeltaY: -1, phase: 0, isContinuous: false),
            lineY: -1,
            lineX: 0
        ))
        #expect(PlaybackScrollPlanner.shouldUseLineScroll(
            payload: ScrollPayload(deltaX: 0, deltaY: -12, lineDeltaX: 0, lineDeltaY: -1, phase: 0, isContinuous: false),
            lineY: -1,
            lineX: 0
        ))
        #expect(!PlaybackScrollPlanner.shouldUseLineScroll(
            payload: ScrollPayload(deltaX: 0, deltaY: -8, lineDeltaX: 0, lineDeltaY: -1, phase: 0, isContinuous: true),
            lineY: -1,
            lineX: 0
        ))

        var wheel = RecordedEvent.make(.scrollWheel, time: 0.1, x: 100, y: 100, scrollDeltaY: -12, scrollDeltaX: 0)
        wheel.scrollPayload = ScrollPayload(deltaX: 0, deltaY: 0, lineDeltaX: 0, lineDeltaY: -1, phase: 0, isContinuous: false)
        let wheelSpec = PlaybackScrollPlanner.spec(for: wheel)
        #expect(wheelSpec.units == .line)
        #expect(wheelSpec.wheelY == -1)

        var trackpad = RecordedEvent.make(.scrollWheel, time: 0.1, x: 100, y: 100, scrollDeltaY: -8, scrollDeltaX: 0)
        trackpad.scrollPayload = ScrollPayload(deltaX: 0, deltaY: -8, lineDeltaX: 0, lineDeltaY: -1, phase: 1, isContinuous: true)
        let trackpadSpec = PlaybackScrollPlanner.spec(for: trackpad)
        #expect(trackpadSpec.units == .pixel)
        #expect(trackpadSpec.wheelY == -8)
        #expect(trackpadSpec.isContinuous)
    }
}

private struct PostedInput: Equatable, Sendable {
    var event: RecordedEvent
    var point: CGPoint
}

private final class PostedInputRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[PostedInput]>(initialState: [])

    func append(event: RecordedEvent, point: CGPoint) {
        lock.withLock {
            $0.append(PostedInput(event: event, point: point))
        }
    }

    func snapshot() -> [PostedInput] {
        lock.withLock { $0 }
    }
}

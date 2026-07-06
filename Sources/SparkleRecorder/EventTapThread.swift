import Foundation
import CoreGraphics

public protocol EventTapThreadDelegate: AnyObject {
    func eventTapThread(_ thread: EventTapThread, didReceive type: CGEventType, event: CGEvent)
    func eventTapThreadDidDisableByUserInput(_ thread: EventTapThread)
}

public extension EventTapThreadDelegate {
    func eventTapThreadDidDisableByUserInput(_ thread: EventTapThread) {}
}

public final class EventTapThread: Thread, @unchecked Sendable {
    public weak var delegate: EventTapThreadDelegate?
    
    private let mask: CGEventMask
    private let tapPlace: CGEventTapPlacement
    private let tapOptions: CGEventTapOptions
    
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    private let startupLock = NSLock()
    private let startupSemaphore = DispatchSemaphore(value: 0)
    private var startupResult: Bool?
    private var hasRequestedStart = false
    
    /// A custom magic number we inject into CGEvent.setIntegerValueField(.eventSourceUserData, value: loopbackMagic)
    /// during playback, so we can ignore them here.
    public let loopbackMagic: Int64 = 0x535041524B4C4521 // "SPARKLE!"
    
    public init(mask: CGEventMask, place: CGEventTapPlacement = .headInsertEventTap, options: CGEventTapOptions = .listenOnly) {
        self.mask = mask
        self.tapPlace = place
        self.tapOptions = options
        super.init()
        self.name = "com.sparklerecorder.EventTapThread"
    }

    @discardableResult
    public func startAndWait(timeout: TimeInterval = 2.0) -> Bool {
        let shouldStart: Bool
        startupLock.lock()
        if let startupResult {
            startupLock.unlock()
            return startupResult
        }
        shouldStart = !hasRequestedStart
        if shouldStart {
            hasRequestedStart = true
        }
        startupLock.unlock()

        if shouldStart {
            start()
        }

        let deadline = DispatchTime.now() + .milliseconds(Int(timeout * 1_000))
        guard startupSemaphore.wait(timeout: deadline) == .success else {
            return false
        }

        startupLock.lock()
        let result = startupResult ?? false
        startupLock.unlock()
        return result
    }
    
    public override func main() {
        self.runLoop = CFRunLoopGetCurrent()
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let thread = Unmanaged<EventTapThread>.fromOpaque(refcon).takeUnretainedValue()
            
            // Loopback filter
            if type != .tapDisabledByTimeout && type != .tapDisabledByUserInput {
                let userData = event.getIntegerValueField(.eventSourceUserData)
                if userData == thread.loopbackMagic {
                    // Ignore our own synthetic events
                    return Unmanaged.passUnretained(event)
                }
            }
            
            // Different disabled policies
            if type == .tapDisabledByTimeout {
                NSLog("SparkleRecorder: Event tap disabled by timeout, attempting to re-enable...")
                if let tap = thread.tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            } else if type == .tapDisabledByUserInput {
                NSLog("SparkleRecorder: Event tap disabled by user input (e.g., Secure Input). Must wait for context change.")
                thread.delegate?.eventTapThreadDidDisableByUserInput(thread)
                // It might not re-enable immediately if secure input is active, but we try.
                if let tap = thread.tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            
            thread.delegate?.eventTapThread(thread, didReceive: type, event: event)
            
            return Unmanaged.passUnretained(event)
        }
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: tapPlace,
            options: tapOptions,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            NSLog("SparkleRecorder: failed to create event tap in EventTapThread.")
            signalStartup(false)
            return
        }
        
        self.tap = newTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        signalStartup(true)
        
        // Start run loop
        CFRunLoopRun()
        
        // Teardown once loop stops
        teardownTap()
    }
    
    public func stop() {
        // Stop the runloop asynchronously
        if let runLoop = self.runLoop {
            CFRunLoopStop(runLoop)
        }
        // Force teardown on the caller thread to ensure tap is immediately invalidated
        teardownTap()
    }
    
    private func teardownTap() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        if let source = runLoopSource, let runLoop = runLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            self.runLoopSource = nil
        }
    }

    private func signalStartup(_ result: Bool) {
        let shouldSignal: Bool
        startupLock.lock()
        shouldSignal = startupResult == nil
        if shouldSignal {
            startupResult = result
        }
        startupLock.unlock()

        if shouldSignal {
            startupSemaphore.signal()
        }
    }
}

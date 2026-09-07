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
    
    /// The tap and source are owned exclusively by this thread's `main()`.
    /// Other threads may only request that the run loop stop; they must never
    /// disable or invalidate these CoreGraphics objects directly.
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let lifecycleLock = NSLock()
    private var runLoop: CFRunLoop?
    private var stopRequested = false

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
        guard let currentRunLoop = CFRunLoopGetCurrent() else {
            signalStartup(false)
            return
        }

        lifecycleLock.lock()
        self.runLoop = currentRunLoop
        let shouldAbortBeforeSetup = stopRequested
        lifecycleLock.unlock()

        if shouldAbortBeforeSetup {
            signalStartup(false)
            clearOwnedRunLoop(currentRunLoop)
            return
        }

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
        CFRunLoopAddSource(currentRunLoop, source, .commonModes)

        if isStopRequested {
            signalStartup(false)
            teardownTap(on: currentRunLoop)
            clearOwnedRunLoop(currentRunLoop)
            return
        }

        CGEvent.tapEnable(tap: newTap, enable: true)
        signalStartup(true)

        if !isStopRequested {
            CFRunLoopRun()
        }

        // Teardown has one owner: the event-tap thread. `stop()` only requests
        // run-loop termination, so no other thread can race an invalidate against
        // this final remove/invalidate sequence.
        teardownTap(on: currentRunLoop)
        clearOwnedRunLoop(currentRunLoop)
    }

    public func stop() {
        lifecycleLock.lock()
        stopRequested = true
        let ownedRunLoop = runLoop
        lifecycleLock.unlock()

        guard let ownedRunLoop else { return }
        CFRunLoopStop(ownedRunLoop)
        CFRunLoopWakeUp(ownedRunLoop)
    }

    private var isStopRequested: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return stopRequested
    }

    private func clearOwnedRunLoop(_ ownedRunLoop: CFRunLoop) {
        lifecycleLock.lock()
        if runLoop === ownedRunLoop {
            runLoop = nil
        }
        lifecycleLock.unlock()
    }

    /// Must be called only from `main()` on the EventTapThread.
    private func teardownTap(on ownedRunLoop: CFRunLoop) {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(ownedRunLoop, source, .commonModes)
            runLoopSource = nil
        }
        if let tap {
            // Invalidating the CFMachPort stops it receiving messages and also
            // invalidates its run-loop source. Avoid a separate tapEnable(false)
            // call during destruction; re-enabling is only needed for the
            // timeout/Secure Input recovery path while the tap is still live.
            CFMachPortInvalidate(tap)
            self.tap = nil
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

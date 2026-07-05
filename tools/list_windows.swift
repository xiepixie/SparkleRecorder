import Foundation
import ScreenCaptureKit

@available(macOS 13.0, *)
func run() async {
    do {
        let content = try await SCShareableContent.current
        for window in content.windows {
            if let title = window.title, !title.isEmpty {
                let bid = window.owningApplication?.bundleIdentifier ?? "nil"
                print("Title: '\(title)' - Bundle: '\(bid)'")
            }
        }
    } catch {
        print("Error: \(error)")
    }
}

if #available(macOS 13.0, *) {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await run()
        semaphore.signal()
    }
    semaphore.wait()
}

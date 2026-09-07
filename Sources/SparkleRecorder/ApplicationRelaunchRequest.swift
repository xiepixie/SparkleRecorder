import Foundation

struct ApplicationRelaunchRequest: Equatable, Sendable {
    var applicationURL: URL
    var isApplicationBundle: Bool

    func makeProcess() -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            isApplicationBundle
                ? "sleep 0.5; /usr/bin/open \"$1\""
                : "sleep 0.5; exec \"$1\"",
            "sparklerecorder-relaunch",
            applicationURL.path,
        ]
        return process
    }
}

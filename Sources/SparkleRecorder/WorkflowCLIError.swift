import Foundation

/// Stable machine-facing error payload shared by workflow CLI capabilities.
package struct WorkflowCLIError: Error {
    package var code: String
    package var message: String
    package var path: String?

    package init(_ code: String, _ message: String, path: String? = nil) {
        self.code = code
        self.message = message
        self.path = path
    }
}

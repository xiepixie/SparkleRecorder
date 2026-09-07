import Foundation

private final class WorkflowCLIAsyncResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func set(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<Value, Error>? {
        lock.lock()
        let current = result
        lock.unlock()
        return current
    }
}

package func waitForWorkflowCLIAsync<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) throws -> Value {
    let semaphore = DispatchSemaphore(value: 0)
    let box = WorkflowCLIAsyncResultBox<Value>()

    Task {
        do {
            box.set(.success(try await operation()))
        } catch {
            box.set(.failure(error))
        }
        semaphore.signal()
    }

    semaphore.wait()
    guard let result = box.get() else {
        throw WorkflowCLIError(
            "asyncBridgeFailed",
            "Workflow CLI async operation did not return a result."
        )
    }
    return try result.get()
}

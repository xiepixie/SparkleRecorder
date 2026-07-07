import Foundation

public struct AutomationResourceRequest: Equatable, Sendable {
    public var runID: UUID
    public var resource: AutomationResource
    public var requestedAt: Date
    public var leaseTimeout: TimeInterval?

    public init(
        runID: UUID,
        resource: AutomationResource,
        requestedAt: Date,
        leaseTimeout: TimeInterval? = nil
    ) {
        self.runID = runID
        self.resource = resource
        self.requestedAt = requestedAt
        self.leaseTimeout = leaseTimeout.map { max(0, $0) }
    }
}

public enum AutomationResourceLeaseResult: Equatable, Sendable {
    case acquired(AutomationResourceLease)
    case denied(resource: AutomationResource)

    public var lease: AutomationResourceLease? {
        if case .acquired(let lease) = self {
            return lease
        }
        return nil
    }

    public var deniedResource: AutomationResource? {
        if case .denied(let resource) = self {
            return resource
        }
        return nil
    }

    public func action(runID: UUID, at: Date) -> AutomationAction {
        switch self {
        case .acquired(let lease):
            return .resourceLeaseAcquired(runID: runID, lease: lease, at: at)
        case .denied(let resource):
            return .resourceLeaseDenied(runID: runID, resource: resource, at: at)
        }
    }
}

public actor AutomationResourceLeaseStore {
    private var leasesByResource: [AutomationResource: AutomationResourceLease]

    public init(initialLeases: [AutomationResourceLease] = []) {
        self.leasesByResource = Dictionary(
            uniqueKeysWithValues: initialLeases.map { ($0.resource, $0) }
        )
    }

    public func acquire(
        _ request: AutomationResourceRequest,
        leaseID: UUID = UUID()
    ) -> AutomationResourceLeaseResult {
        if let existingLease = leasesByResource[request.resource] {
            guard existingLease.runID == request.runID else {
                return .denied(resource: request.resource)
            }
            return .acquired(existingLease)
        }

        let expiresAt = request.leaseTimeout.map {
            request.requestedAt.addingTimeInterval($0)
        }
        let lease = AutomationResourceLease(
            id: leaseID,
            runID: request.runID,
            resource: request.resource,
            acquiredAt: request.requestedAt,
            expiresAt: expiresAt
        )
        leasesByResource[request.resource] = lease
        return .acquired(lease)
    }

    public func release(leaseID: UUID) {
        leasesByResource = leasesByResource.filter { _, lease in
            lease.id != leaseID
        }
    }

    public func panicRelease(runID: UUID) {
        leasesByResource = leasesByResource.filter { _, lease in
            lease.runID != runID
        }
    }

    @discardableResult
    public func releaseExpired(at date: Date) -> [AutomationResourceLease] {
        let expiredLeases = leasesByResource.values.filter { lease in
            guard let expiresAt = lease.expiresAt else {
                return false
            }
            return expiresAt <= date
        }

        guard !expiredLeases.isEmpty else {
            return []
        }

        let expiredIDs = Set(expiredLeases.map(\.id))
        leasesByResource = leasesByResource.filter { _, lease in
            !expiredIDs.contains(lease.id)
        }
        return expiredLeases.sorted(by: Self.leaseSort)
    }

    public func currentLease(for resource: AutomationResource) -> AutomationResourceLease? {
        leasesByResource[resource]
    }

    public func allLeases() -> [AutomationResourceLease] {
        leasesByResource.values.sorted(by: Self.leaseSort)
    }

    private static func leaseSort(
        _ left: AutomationResourceLease,
        _ right: AutomationResourceLease
    ) -> Bool {
        if left.acquiredAt != right.acquiredAt {
            return left.acquiredAt < right.acquiredAt
        }
        if left.resource.rawValue != right.resource.rawValue {
            return left.resource.rawValue < right.resource.rawValue
        }
        return left.id.uuidString < right.id.uuidString
    }
}

public struct AutomationResourceArbiterClient: Sendable {
    public var acquire: @Sendable (AutomationResourceRequest) async -> AutomationResourceLeaseResult
    public var release: @Sendable (_ leaseID: UUID) async -> Void
    public var panicRelease: @Sendable (_ runID: UUID) async -> Void
    public var releaseExpired: @Sendable (_ date: Date) async -> [AutomationResourceLease]

    public init(
        acquire: @escaping @Sendable (AutomationResourceRequest) async -> AutomationResourceLeaseResult,
        release: @escaping @Sendable (_ leaseID: UUID) async -> Void,
        panicRelease: @escaping @Sendable (_ runID: UUID) async -> Void,
        releaseExpired: @escaping @Sendable (_ date: Date) async -> [AutomationResourceLease] = { _ in [] }
    ) {
        self.acquire = acquire
        self.release = release
        self.panicRelease = panicRelease
        self.releaseExpired = releaseExpired
    }

    public func acquireAction(for request: AutomationResourceRequest) async -> AutomationAction {
        let result = await acquire(request)
        return result.action(runID: request.runID, at: request.requestedAt)
    }

    public static func live(
        store: AutomationResourceLeaseStore = AutomationResourceLeaseStore(),
        leaseID: @escaping @Sendable () -> UUID = { UUID() }
    ) -> AutomationResourceArbiterClient {
        AutomationResourceArbiterClient(
            acquire: { request in
                await store.acquire(request, leaseID: leaseID())
            },
            release: { leaseID in
                await store.release(leaseID: leaseID)
            },
            panicRelease: { runID in
                await store.panicRelease(runID: runID)
            },
            releaseExpired: { date in
                await store.releaseExpired(at: date)
            }
        )
    }
}

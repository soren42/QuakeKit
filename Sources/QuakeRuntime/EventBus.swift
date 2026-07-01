import Foundation

public final class RuntimeEventBus {
    public typealias SubscriptionID = UUID
    public typealias Handler = (RuntimeEvent) -> Void

    private var handlers: [SubscriptionID: Handler] = [:]

    public init() {}

    @discardableResult
    public func subscribe(_ handler: @escaping Handler) -> SubscriptionID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    public func unsubscribe(_ id: SubscriptionID) {
        handlers.removeValue(forKey: id)
    }

    public func publish(_ event: RuntimeEvent) {
        for handler in handlers.values {
            handler(event)
        }
    }
}

import AppKit

@MainActor final class FakePurchasing: ProPurchasing {
    var availablePrice: String? = "¥12.00"
    var active = false
    var outcome: ProPurchaseResult = .cancelled
    var fail = false
    var buys = 0
    var restoreActive = false
    var continuation: AsyncStream<Void>.Continuation?
    func displayPrice() async throws -> String? { availablePrice }
    func purchase() async throws -> ProPurchaseResult {
        buys += 1
        if fail { throw NSError(domain: "Unverified purchase", code: 1) }
        return outcome
    }
    func entitled() async -> Bool { active }
    func restore() async throws { active = restoreActive }
    func updates() -> AsyncStream<Void> { AsyncStream { continuation = $0 } }
}
@main struct Checks {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let suite = "Qingyu.ProChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "isPro") // A forged local flag cannot grant an entitlement.
        let service = FakePurchasing()
        let store = ProStore(service: service, defaults: defaults)
        precondition(!store.isPro && !store.highDefinition)
        await store.load()
        precondition(store.price == "¥12.00")
        await store.buy()
        precondition(!store.isPro && store.message == nil, "cancellation")
        service.outcome = .pending
        await store.buy()
        precondition(!store.isPro && store.message?.contains("等待批准") == true)
        service.outcome = .purchased
        await store.buy()
        precondition(!store.isPro, "a purchase callback alone must not unlock")
        service.fail = true
        await store.buy()
        precondition(!store.isPro && store.message != nil, "verification failure")
        service.fail = false; service.active = true
        await store.buy()
        precondition(store.isPro && store.highDefinition)
        store.prefersHD = false
        precondition(store.isPro && !store.highDefinition)
        precondition(!ProStore(service: service, defaults: defaults).prefersHD)
        service.active = false
        await store.refresh()
        precondition(!store.isPro && !store.highDefinition, "revoked entitlements are removed")
        service.restoreActive = true
        await store.restorePurchases()
        precondition(store.isPro, "restore grants verified entitlement")
        service.restoreActive = false
        await store.restorePurchases()
        precondition(!store.isPro, "restore cannot retain stale entitlement")
        service.availablePrice = nil
        await store.load()
        let buys = service.buys
        await store.buy()
        precondition(service.buys == buys && !store.isPro, "unavailable product cannot be purchased")
        store.start()
        for _ in 0..<5 { await Task.yield() }
        service.active = true; service.continuation?.yield(())
        for _ in 0..<20 { await Task.yield() }
        precondition(store.isPro, "transaction updates refresh entitlement")
        service.active = false; service.continuation?.yield(())
        for _ in 0..<20 { await Task.yield() }
        precondition(!store.isPro, "refund update removes entitlement")
        service.continuation?.finish()
        print("Pro checks passed: trusted entitlement gate, localized price, cancellation, pending, failed verification, restore, revocation, transaction updates, unavailable product")
    }
}

import AppKit
import SwiftUI
import StoreKit

// Entitlements come only from verified StoreKit transactions, never a local unlock flag.
enum ProPurchaseResult { case purchased, pending, cancelled }
@MainActor protocol ProPurchasing {
    func displayPrice() async throws -> String?
    func purchase() async throws -> ProPurchaseResult
    func entitled() async -> Bool
    func restore() async throws
    func updates() -> AsyncStream<Void>
}

@MainActor final class AppleProPurchasing: ProPurchasing {
    static let productID = "com.shitu.capture.pro.lifetime"
    private var product: Product?
    func displayPrice() async throws -> String? {
        product = try await Product.products(for: [Self.productID]).first(where: { $0.id == Self.productID && $0.type == .nonConsumable })
        return product?.displayPrice
    }
    func purchase() async throws -> ProPurchaseResult {
        guard let product else { throw ProStoreError.unavailable }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID, transaction.revocationDate == nil else { throw ProStoreError.unverified }
            await transaction.finish()
            return .purchased
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: throw ProStoreError.unavailable
        }
    }
    func entitled() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID, transaction.productType == .nonConsumable,
               transaction.revocationDate == nil { return true }
        }
        return false
    }
    func restore() async throws { try await AppStore.sync() }
    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { break }
                    if case .verified(let transaction) = result, transaction.productID == Self.productID {
                        // Includes refunds/revocations: refresh the authoritative entitlement list.
                        await transaction.finish(); continuation.yield(())
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
private enum ProStoreError: LocalizedError {
    case unavailable, unverified
    var errorDescription: String? {
        switch self {
        case .unavailable: "商品暂不可用，请稍后重试。"
        case .unverified: "无法验证购买结果，尚未解锁。请尝试恢复购买。"
        }
    }
}

@MainActor final class ProStore: ObservableObject {
    static let shared = ProStore()
    @Published private(set) var isPro = false
    @Published private(set) var price: String?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published var prefersHD: Bool { didSet { defaults.set(prefersHD, forKey: "qingyu.pro.preferHD") } }
    var highDefinition: Bool { isPro && prefersHD }
    private let service: ProPurchasing
    private let defaults: UserDefaults
    private var observer: Task<Void, Never>?
    private var refreshGeneration = 0
    init(service: ProPurchasing? = nil, defaults: UserDefaults = .standard) {
        self.service = service ?? AppleProPurchasing(); self.defaults = defaults
        prefersHD = defaults.object(forKey: "qingyu.pro.preferHD") as? Bool ?? true
    }
    func start() {
        guard observer == nil else { return }
        let stream = service.updates()
        observer = Task { [weak self] in
            await self?.refresh()
            for await _ in stream {
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }
    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let available = await service.entitled()
        guard generation == refreshGeneration else { return }
        isPro = available
    }
    func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        await refresh()
        do { price = try await service.displayPrice(); message = price == nil && !isPro ? "商品暂不可用，请稍后重试。" : nil }
        catch { message = "无法连接 App Store，请稍后重试。"; price = nil }
    }
    func buy() async {
        guard !busy, price != nil, !isPro else { return }; busy = true; defer { busy = false }
        message = nil
        do {
            switch try await service.purchase() {
            case .purchased:
                await refresh()
                message = isPro ? "Pro 已解锁，感谢支持轻屿。" : "购买正在同步，请稍后恢复购买。"
            case .pending: message = "购买正在等待批准，批准后会自动解锁。"
            case .cancelled: break
            }
        } catch { message = error.localizedDescription }
    }
    func restorePurchases() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await service.restore(); await refresh(); message = isPro ? "已恢复 Pro。" : "当前 Apple 账户没有可恢复的 Pro 购买。" }
        catch { message = "恢复购买失败，请检查网络后重试。" }
    }
    deinit { observer?.cancel() }
}

struct ProSettings: View {
    @ObservedObject var store: ProStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("轻屿 Pro", systemImage: "sparkles").font(.title3.bold())
                Spacer()
                if store.isPro { Label("已解锁", systemImage: "checkmark.seal.fill").foregroundStyle(WorkspaceTheme.accent(scheme)).font(.callout) }
                else { Text(store.price.map { "\($0) · 一次性买断" } ?? "计划售价 ¥12 · 一次性买断").font(.callout) }
            }
            Text("高清 PNG / GIF · 图文教程 · 文件暂存篮 · 工作现场 · 截图对比").font(.callout)
            Text("PNG 保留 Retina 原始像素，GIF 最高 1920 像素 / 20 fps。办公工具在本机处理资料。").font(.caption).foregroundStyle(.secondary)
            Text("标准画质：PNG 逻辑尺寸，GIF 960 像素 / 10 fps。GIF 仍有 256 色格式限制；实际分辨率不超过录制源。").font(.caption).foregroundStyle(.secondary)
            if store.isPro {
                Toggle("默认使用高清画质", isOn: $store.prefersHD)
            } else {
                Button(store.busy ? "正在连接…" : "解锁轻屿 Pro") { Task { await store.buy() } }
                    .buttonStyle(.borderedProminent).disabled(store.busy || store.price == nil)
            }
            HStack {
                Button("恢复购买") { Task { await store.restorePurchases() } }
                if store.price == nil { Button("重试连接") { Task { await store.load() } } }
                if store.busy { ProgressView().controlSize(.small) }
            }.font(.caption).disabled(store.busy)
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.padding(18).background(WorkspaceTheme.accent(scheme).opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .task { await store.load() }
    }
}

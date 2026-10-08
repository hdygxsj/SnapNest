import Foundation
import Combine
import ServiceManagement

@MainActor
public protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

@MainActor
public final class NativeLoginItemService: LoginItemService {
    public init() {}
    public var status: SMAppService.Status { SMAppService.mainApp.status }
    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() async throws { try await SMAppService.mainApp.unregister() }
}

@MainActor
public final class LoginItemController: ObservableObject {
    @Published public private(set) var status: SMAppService.Status
    @Published public private(set) var isChanging = false
    @Published public private(set) var errorMessage: String?
    private let service: LoginItemService
    public init(service: LoginItemService) { self.service = service; status = service.status }
    public var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    public func refresh() { status = service.status }
    public func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        isChanging = true
        errorMessage = nil
        defer { refresh(); isChanging = false }
        do {
            let current = service.status
            if enabled {
                if current != .enabled && current != .requiresApproval { try service.register() }
            } else if current == .enabled || current == .requiresApproval {
                try await service.unregister()
            }
        } catch {
            errorMessage = "无法更新登录启动设置：\(error.localizedDescription)"
        }
    }
    public func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

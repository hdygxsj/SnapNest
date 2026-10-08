import Foundation
import ServiceManagement
import ShituCore

@MainActor
private final class TestLoginService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var denyRegistration = false
    var needApproval = false
    func register() throws {
        if denyRegistration { throw NSError(domain: "LoginTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration denied"]) }
        status = needApproval ? .requiresApproval : .enabled
    }
    func unregister() async throws { status = .notRegistered }
}

@MainActor
func checkLoginItems() async {
    let service = TestLoginService()
    let controller = LoginItemController(service: service)
    await controller.setEnabled(true)
    XCTAssertEqual(controller.status, .enabled)
    await controller.setEnabled(false)
    XCTAssertEqual(controller.isRegistered, false)
    service.denyRegistration = true
    await controller.setEnabled(true)
    XCTAssertEqual(controller.isRegistered, false)
    XCTAssertEqual(controller.errorMessage != nil, true)
    service.denyRegistration = false; service.needApproval = true
    await controller.setEnabled(true)
    XCTAssertEqual(controller.status, .requiresApproval)
    XCTAssertEqual(controller.isRegistered, true)
    XCTAssertEqual(controller.errorMessage == nil, true)
    service.status = .notRegistered
    controller.refresh()
    XCTAssertEqual(controller.isRegistered, false)
    XCTAssertEqual(controller.isChanging, false)
}

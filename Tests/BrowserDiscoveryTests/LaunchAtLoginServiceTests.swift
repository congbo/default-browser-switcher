import XCTest
@testable import DefaultBrowserSwitcher

@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {
    func testRefreshMapsControllerStatusesToTruthfulStates() async {
        let controller = FakeLaunchAtLoginController(statuses: [
            .enabled,
            .notRegistered,
            .requiresApproval,
            .notFound,
            .unknown
        ])
        let service = LaunchAtLoginService(controller: controller)

        await service.refresh()
        XCTAssertEqual(service.model.resolvedStatus, .enabled)
        XCTAssertEqual(service.model.detailState, .enabled)
        XCTAssertNil(service.model.errorMessage)

        await service.refresh()
        XCTAssertEqual(service.model.resolvedStatus, .disabled)
        XCTAssertEqual(service.model.detailState, .disabled)
        XCTAssertNil(service.model.errorMessage)

        await service.refresh()
        XCTAssertEqual(service.model.resolvedStatus, .approvalRequired)
        XCTAssertEqual(service.model.detailState, .approvalRequired)
        XCTAssertNil(service.model.errorMessage)

        await service.refresh()
        XCTAssertEqual(service.model.resolvedStatus, .disabled)
        XCTAssertEqual(service.model.detailState, .neutral)
        XCTAssertNil(service.model.errorMessage)

        await service.refresh()
        XCTAssertEqual(service.model.resolvedStatus, .disabled)
        XCTAssertEqual(service.model.detailState, .neutral)
        XCTAssertNil(service.model.errorMessage)
    }

    func testSetEnabledRegistersFromDisabledStateAndPublishesEnabledStatus() async {
        let controller = FakeLaunchAtLoginController(statuses: [.notRegistered, .enabled])
        let service = LaunchAtLoginService(controller: controller)

        await service.refresh()
        await service.setEnabled(true)

        XCTAssertEqual(controller.registerCallCount, 1)
        XCTAssertEqual(controller.unregisterCallCount, 0)
        XCTAssertEqual(service.model.resolvedStatus, .enabled)
        XCTAssertEqual(service.model.detailState, .enabled)
        XCTAssertFalse(service.model.isApplyingChange)
        XCTAssertNil(service.model.errorMessage)
    }

    func testSetEnabledRegistersFromNotFoundStateAndPublishesEnabledStatus() async {
        let controller = FakeLaunchAtLoginController(statuses: [.notFound, .enabled])
        let service = LaunchAtLoginService(controller: controller)

        await service.refresh()
        await service.setEnabled(true)

        XCTAssertEqual(controller.registerCallCount, 1)
        XCTAssertEqual(controller.unregisterCallCount, 0)
        XCTAssertEqual(service.model.resolvedStatus, .enabled)
        XCTAssertEqual(service.model.detailState, .enabled)
        XCTAssertFalse(service.model.isApplyingChange)
        XCTAssertNil(service.model.errorMessage)
    }

    func testSetEnabledUnregistersFromEnabledStateAndPublishesDisabledStatus() async {
        let controller = FakeLaunchAtLoginController(statuses: [.enabled, .notRegistered])
        let service = LaunchAtLoginService(controller: controller)

        await service.refresh()
        await service.setEnabled(false)

        XCTAssertEqual(controller.registerCallCount, 0)
        XCTAssertEqual(controller.unregisterCallCount, 1)
        XCTAssertEqual(service.model.resolvedStatus, .disabled)
        XCTAssertEqual(service.model.detailState, .disabled)
        XCTAssertFalse(service.model.isApplyingChange)
        XCTAssertNil(service.model.errorMessage)
    }

    func testRegisterFailurePreservesDisabledStateAndSurfacesVisibleError() async {
        let controller = FakeLaunchAtLoginController(
            statuses: [.notRegistered],
            registerError: LaunchAtLoginFixtureError.registerFailed
        )
        let service = LaunchAtLoginService(controller: controller)

        await service.refresh()
        await service.setEnabled(true)

        XCTAssertEqual(service.model.resolvedStatus, .disabled)
        XCTAssertEqual(service.model.detailState, .disabled)
        XCTAssertEqual(service.model.errorMessage, LaunchAtLoginFixtureError.registerFailed.errorDescription)
        XCTAssertEqual(controller.registerCallCount, 1)
    }

    func testUnregisterFailurePreservesEnabledStateAndSurfacesVisibleError() async {
        let controller = FakeLaunchAtLoginController(
            statuses: [.enabled],
            unregisterError: LaunchAtLoginFixtureError.unregisterFailed
        )
        let service = LaunchAtLoginService(controller: controller)

        await service.refresh()
        await service.setEnabled(false)

        XCTAssertEqual(service.model.resolvedStatus, .enabled)
        XCTAssertEqual(service.model.detailState, .enabled)
        XCTAssertEqual(service.model.errorMessage, LaunchAtLoginFixtureError.unregisterFailed.errorDescription)
        XCTAssertEqual(controller.unregisterCallCount, 1)
    }

    func testSetEnabledIgnoresRequestsWhenToggleStateIsAlreadyCurrent() async {
        let controller = FakeLaunchAtLoginController(statuses: [.enabled])
        let service = LaunchAtLoginService(controller: controller)

        await service.refresh()
        await service.setEnabled(true)
        XCTAssertEqual(service.model.resolvedStatus, .enabled)
        XCTAssertEqual(controller.registerCallCount, 0)
    }
}

private final class FakeLaunchAtLoginController: LaunchAtLoginControlling {
    private var queuedStatuses: [LaunchAtLoginService.ControllerStatus]
    private let registerError: Error?
    private let unregisterError: Error?

    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(
        statuses: [LaunchAtLoginService.ControllerStatus],
        registerError: Error? = nil,
        unregisterError: Error? = nil
    ) {
        self.queuedStatuses = statuses
        self.registerError = registerError
        self.unregisterError = unregisterError
    }

    func currentStatus() async -> LaunchAtLoginService.ControllerStatus {
        if queuedStatuses.count > 1 {
            return queuedStatuses.removeFirst()
        }

        return queuedStatuses.first ?? .unknown
    }

    func register() async throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
    }

    func unregister() async throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
    }
}

private enum LaunchAtLoginFixtureError: LocalizedError {
    case registerFailed
    case unregisterFailed

    var errorDescription: String? {
        switch self {
        case .registerFailed:
            return "Register failed"
        case .unregisterFailed:
            return "Unregister failed"
        }
    }
}

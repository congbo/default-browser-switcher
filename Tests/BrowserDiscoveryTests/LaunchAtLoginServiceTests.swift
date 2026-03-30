import XCTest
@testable import DefaultBrowserSwitcher

@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {
    func testRefreshMapsVisibleControllerStatusesToTruthfulStates() async {
        let controller = FakeLaunchAtLoginController(statuses: [
            .enabled,
            .notRegistered,
            .requiresApproval,
            .notFound,
            .unknown
        ])
        let environmentProbe = FakeLaunchAtLoginEnvironmentProbe(
            distributions: [
                .xcodeDevelopmentRun,
                .xcodeDevelopmentRun,
                .xcodeDevelopmentRun,
                .xcodeDevelopmentRun,
                .supportedInstalledBuild
            ]
        )
        let service = LaunchAtLoginService(controller: controller, environmentProbe: environmentProbe)

        await service.refresh()
        XCTAssertTrue(service.model.isVisible)
        XCTAssertEqual(service.model.resolvedStatus, .enabled)
        XCTAssertNil(service.model.errorMessage)

        await service.refresh()
        XCTAssertTrue(service.model.isVisible)
        XCTAssertEqual(service.model.resolvedStatus, .disabled)
        XCTAssertNil(service.model.errorMessage)

        await service.refresh()
        XCTAssertTrue(service.model.isVisible)
        XCTAssertEqual(service.model.resolvedStatus, .approvalRequired)
        XCTAssertNil(service.model.errorMessage)

        await service.refresh()
        XCTAssertTrue(service.model.isVisible)
        XCTAssertEqual(service.model.resolvedStatus, .unavailable)
        XCTAssertNil(service.model.errorMessage)

        await service.refresh()
        XCTAssertTrue(service.model.isVisible)
        XCTAssertEqual(service.model.resolvedStatus, .unavailable)
        XCTAssertNil(service.model.errorMessage)
    }

    func testRefreshHidesSectionForUnsupportedDistribution() async {
        let controller = FakeLaunchAtLoginController(statuses: [.notFound])
        let service = LaunchAtLoginService(
            controller: controller,
            environmentProbe: FakeLaunchAtLoginEnvironmentProbe(distributions: [.unsupportedDistribution])
        )

        await service.refresh()

        XCTAssertFalse(service.model.isVisible)
        XCTAssertNil(service.model.resolvedStatus)
        XCTAssertNil(service.model.errorMessage)
    }

    func testRefreshShowsSectionForXcodeDevelopmentRunEvenWithoutSupportedSigning() async {
        let controller = FakeLaunchAtLoginController(statuses: [.notFound])
        let service = LaunchAtLoginService(
            controller: controller,
            environmentProbe: FakeLaunchAtLoginEnvironmentProbe(distributions: [.xcodeDevelopmentRun])
        )

        await service.refresh()

        XCTAssertTrue(service.model.isVisible)
        XCTAssertEqual(service.model.resolvedStatus, .unavailable)
    }

    func testRefreshShowsSectionForSupportedInstalledBuild() async {
        let controller = FakeLaunchAtLoginController(statuses: [.notRegistered])
        let service = LaunchAtLoginService(
            controller: controller,
            environmentProbe: FakeLaunchAtLoginEnvironmentProbe(distributions: [.supportedInstalledBuild])
        )

        await service.refresh()

        XCTAssertTrue(service.model.isVisible)
        XCTAssertEqual(service.model.resolvedStatus, .disabled)
    }

    func testSetEnabledRegistersFromDisabledStateAndPublishesEnabledStatus() async {
        let controller = FakeLaunchAtLoginController(statuses: [.notRegistered, .enabled])
        let service = LaunchAtLoginService(
            controller: controller,
            environmentProbe: FakeLaunchAtLoginEnvironmentProbe(distributions: [.supportedInstalledBuild, .supportedInstalledBuild])
        )

        await service.refresh()
        await service.setEnabled(true)

        XCTAssertEqual(controller.registerCallCount, 1)
        XCTAssertEqual(controller.unregisterCallCount, 0)
        XCTAssertEqual(service.model.resolvedStatus, .enabled)
        XCTAssertFalse(service.model.isApplyingChange)
        XCTAssertNil(service.model.errorMessage)
    }

    func testSetEnabledUnregistersFromEnabledStateAndPublishesDisabledStatus() async {
        let controller = FakeLaunchAtLoginController(statuses: [.enabled, .notRegistered])
        let service = LaunchAtLoginService(
            controller: controller,
            environmentProbe: FakeLaunchAtLoginEnvironmentProbe(distributions: [.supportedInstalledBuild, .supportedInstalledBuild])
        )

        await service.refresh()
        await service.setEnabled(false)

        XCTAssertEqual(controller.registerCallCount, 0)
        XCTAssertEqual(controller.unregisterCallCount, 1)
        XCTAssertEqual(service.model.resolvedStatus, .disabled)
        XCTAssertFalse(service.model.isApplyingChange)
        XCTAssertNil(service.model.errorMessage)
    }

    func testRegisterFailurePreservesDisabledStateAndSurfacesVisibleError() async {
        let controller = FakeLaunchAtLoginController(
            statuses: [.notRegistered],
            registerError: LaunchAtLoginFixtureError.registerFailed
        )
        let service = LaunchAtLoginService(
            controller: controller,
            environmentProbe: FakeLaunchAtLoginEnvironmentProbe(distributions: [.supportedInstalledBuild])
        )

        await service.refresh()
        await service.setEnabled(true)

        XCTAssertEqual(service.model.resolvedStatus, .disabled)
        XCTAssertEqual(service.model.errorMessage, LaunchAtLoginFixtureError.registerFailed.errorDescription)
        XCTAssertEqual(controller.registerCallCount, 1)
    }

    func testUnregisterFailurePreservesEnabledStateAndSurfacesVisibleError() async {
        let controller = FakeLaunchAtLoginController(
            statuses: [.enabled],
            unregisterError: LaunchAtLoginFixtureError.unregisterFailed
        )
        let service = LaunchAtLoginService(
            controller: controller,
            environmentProbe: FakeLaunchAtLoginEnvironmentProbe(distributions: [.supportedInstalledBuild])
        )

        await service.refresh()
        await service.setEnabled(false)

        XCTAssertEqual(service.model.resolvedStatus, .enabled)
        XCTAssertEqual(service.model.errorMessage, LaunchAtLoginFixtureError.unregisterFailed.errorDescription)
        XCTAssertEqual(controller.unregisterCallCount, 1)
    }

    func testSetEnabledIgnoresUnsafeStatesAndDoesNotCallController() async {
        let controller = FakeLaunchAtLoginController(statuses: [.requiresApproval, .notFound])
        let service = LaunchAtLoginService(
            controller: controller,
            environmentProbe: FakeLaunchAtLoginEnvironmentProbe(distributions: [.supportedInstalledBuild, .xcodeDevelopmentRun])
        )

        await service.refresh()
        await service.setEnabled(true)
        XCTAssertEqual(service.model.resolvedStatus, .approvalRequired)
        XCTAssertEqual(controller.registerCallCount, 0)

        await service.refresh()
        await service.setEnabled(true)
        XCTAssertEqual(service.model.resolvedStatus, .unavailable)
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

private final class FakeLaunchAtLoginEnvironmentProbe: LaunchAtLoginEnvironmentProbing {
    private var queuedDistributions: [LaunchAtLoginService.Distribution]

    init(distributions: [LaunchAtLoginService.Distribution]) {
        queuedDistributions = distributions
    }

    private func nextDistribution() -> LaunchAtLoginService.Distribution {
        if queuedDistributions.count > 1 {
            return queuedDistributions.removeFirst()
        }

        return queuedDistributions.first ?? .unsupportedDistribution
    }

    func distribution() async -> LaunchAtLoginService.Distribution {
        nextDistribution()
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

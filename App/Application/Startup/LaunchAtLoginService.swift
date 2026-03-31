import Combine
import Foundation
import ServiceManagement

protocol LaunchAtLoginControlling {
    func currentStatus() async -> LaunchAtLoginService.ControllerStatus
    func register() async throws
    func unregister() async throws
}

@MainActor
final class LaunchAtLoginService: ObservableObject {
    enum ControllerStatus: Equatable {
        case enabled
        case notRegistered
        case notFound
        case requiresApproval
        case unknown
    }

    enum ResolvedStatus: Equatable {
        case enabled
        case disabled
        case approvalRequired
    }

    enum DetailState: Equatable {
        case neutral
        case enabled
        case disabled
        case approvalRequired
    }

    struct Model: Equatable {
        var resolvedStatus: ResolvedStatus?
        var detailState: DetailState?
        var isRefreshing = false
        var isApplyingChange = false
        var errorMessage: String?

        var isLoading: Bool {
            resolvedStatus == nil && isRefreshing
        }

        var isToggleOn: Bool {
            resolvedStatus == .enabled
        }

        var canToggle: Bool {
            !isApplyingChange && resolvedStatus != nil
        }
    }

    @Published private(set) var model = Model()

    private let controller: any LaunchAtLoginControlling
    private var hasBootstrapped = false

    init(controller: any LaunchAtLoginControlling = SystemLaunchAtLoginController()) {
        self.controller = controller
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else {
            return
        }

        hasBootstrapped = true
        await refresh()
    }

    func refresh() async {
        guard !model.isRefreshing else {
            return
        }

        let preservedStatus = model.resolvedStatus
        let preservedDetailState = model.detailState
        let isApplyingChange = model.isApplyingChange
        model = Model(
            resolvedStatus: preservedStatus,
            detailState: preservedDetailState,
            isRefreshing: true,
            isApplyingChange: isApplyingChange,
            errorMessage: model.errorMessage
        )

        apply(status: await controller.currentStatus())
    }

    func setEnabled(_ enabled: Bool) async {
        guard !model.isApplyingChange else {
            return
        }

        guard let resolvedStatus = model.resolvedStatus else {
            return
        }

        let detailState = model.detailState

        guard model.isToggleOn != enabled else {
            return
        }

        model = Model(
            resolvedStatus: resolvedStatus,
            detailState: detailState,
            isRefreshing: false,
            isApplyingChange: true,
            errorMessage: nil
        )

        do {
            if enabled {
                try await controller.register()
            } else {
                try await controller.unregister()
            }

            apply(status: await controller.currentStatus())
        } catch {
            model = Model(
                resolvedStatus: resolvedStatus,
                detailState: detailState,
                isRefreshing: false,
                isApplyingChange: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func apply(status: ControllerStatus) {
        let mapped = map(status)
        model = Model(
            resolvedStatus: mapped.resolvedStatus,
            detailState: mapped.detailState,
            isRefreshing: false,
            isApplyingChange: false,
            errorMessage: nil
        )
    }

    private func map(_ status: ControllerStatus) -> (resolvedStatus: ResolvedStatus, detailState: DetailState) {
        switch status {
        case .enabled:
            return (.enabled, .enabled)
        case .notRegistered:
            return (.disabled, .disabled)
        case .notFound, .unknown:
            return (.disabled, .neutral)
        case .requiresApproval:
            return (.approvalRequired, .approvalRequired)
        }
    }
}

struct SystemLaunchAtLoginController: LaunchAtLoginControlling {
    func currentStatus() async -> LaunchAtLoginService.ControllerStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        case .requiresApproval:
            return .requiresApproval
        @unknown default:
            return .unknown
        }
    }

    func register() async throws {
        try SMAppService.mainApp.register()
    }

    func unregister() async throws {
        try await SMAppService.mainApp.unregister()
    }
}

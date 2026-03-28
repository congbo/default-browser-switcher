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
        case unavailable
        case approvalRequired
    }

    struct Model: Equatable {
        var resolvedStatus: ResolvedStatus?
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
            guard !isApplyingChange, let resolvedStatus else {
                return false
            }

            switch resolvedStatus {
            case .enabled, .disabled:
                return true
            case .unavailable, .approvalRequired:
                return false
            }
        }

        var canRetry: Bool {
            !isApplyingChange && (errorMessage != nil || resolvedStatus == .unavailable || resolvedStatus == .approvalRequired)
        }

        var needsAttention: Bool {
            errorMessage != nil || resolvedStatus == .unavailable || resolvedStatus == .approvalRequired
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
        let isApplyingChange = model.isApplyingChange
        model = Model(
            resolvedStatus: preservedStatus,
            isRefreshing: true,
            isApplyingChange: isApplyingChange,
            errorMessage: model.errorMessage
        )

        model = Model(
            resolvedStatus: map(await controller.currentStatus()),
            isRefreshing: false,
            isApplyingChange: false,
            errorMessage: nil
        )
    }

    func setEnabled(_ enabled: Bool) async {
        guard !model.isApplyingChange else {
            return
        }

        guard let resolvedStatus = model.resolvedStatus else {
            return
        }

        guard resolvedStatus == .enabled || resolvedStatus == .disabled else {
            return
        }

        guard model.isToggleOn != enabled else {
            return
        }

        model = Model(
            resolvedStatus: resolvedStatus,
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

            model = Model(
                resolvedStatus: map(await controller.currentStatus()),
                isRefreshing: false,
                isApplyingChange: false,
                errorMessage: nil
            )
        } catch {
            model = Model(
                resolvedStatus: resolvedStatus,
                isRefreshing: false,
                isApplyingChange: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func map(_ status: ControllerStatus) -> ResolvedStatus {
        switch status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .notFound, .unknown:
            return .unavailable
        case .requiresApproval:
            return .approvalRequired
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

import Combine
import Foundation
import Security
import ServiceManagement

protocol LaunchAtLoginControlling {
    func currentStatus() async -> LaunchAtLoginService.ControllerStatus
    func register() async throws
    func unregister() async throws
}

protocol LaunchAtLoginEnvironmentProbing {
    func distribution() async -> LaunchAtLoginService.Distribution
}

@MainActor
final class LaunchAtLoginService: ObservableObject {
    enum Distribution: Equatable {
        case xcodeDevelopmentRun
        case supportedInstalledBuild
        case unsupportedDistribution
    }

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
        var isVisible = true
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
            guard isVisible, !isApplyingChange, let resolvedStatus else {
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
            isVisible && !isApplyingChange && (
                errorMessage != nil
                    || resolvedStatus == .unavailable
                    || resolvedStatus == .approvalRequired
            )
        }

        var needsAttention: Bool {
            isVisible && (
                errorMessage != nil
                || resolvedStatus == .unavailable
                || resolvedStatus == .approvalRequired
            )
        }
    }

    @Published private(set) var model = Model()

    private let controller: any LaunchAtLoginControlling
    private let environmentProbe: any LaunchAtLoginEnvironmentProbing
    private var hasBootstrapped = false

    init(
        controller: any LaunchAtLoginControlling = SystemLaunchAtLoginController(),
        environmentProbe: any LaunchAtLoginEnvironmentProbing = SystemLaunchAtLoginEnvironmentProbe()
    ) {
        self.controller = controller
        self.environmentProbe = environmentProbe
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
        let isVisible = model.isVisible
        let isApplyingChange = model.isApplyingChange
        model = Model(
            isVisible: isVisible,
            resolvedStatus: preservedStatus,
            isRefreshing: true,
            isApplyingChange: isApplyingChange,
            errorMessage: model.errorMessage
        )

        let distribution = await environmentProbe.distribution()
        guard distribution != .unsupportedDistribution else {
            model = Model(isVisible: false)
            return
        }

        let status = await controller.currentStatus()
        model = Model(
            isVisible: true,
            resolvedStatus: map(status),
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

            let status = await controller.currentStatus()

            model = Model(
                isVisible: model.isVisible,
                resolvedStatus: map(status),
                isRefreshing: false,
                isApplyingChange: false,
                errorMessage: nil
            )
        } catch {
            model = Model(
                isVisible: model.isVisible,
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

struct SystemLaunchAtLoginEnvironmentProbe: LaunchAtLoginEnvironmentProbing {
    func distribution() async -> LaunchAtLoginService.Distribution {
        let bundlePath = Bundle.main.bundleURL.resolvingSymlinksInPath().path

        if isXcodeDevelopmentRun(bundlePath: bundlePath) {
            return .xcodeDevelopmentRun
        }

        if isSupportedInstallLocation(bundlePath: bundlePath),
           hasSupportedSigningIdentity(bundleURL: Bundle.main.bundleURL) {
            return .supportedInstalledBuild
        }

        return .unsupportedDistribution
    }

    private func hasSupportedSigningIdentity(bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return false
        }

        var signingInformation: CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInformation)
        guard copyStatus == errSecSuccess,
              let signingInfo = signingInformation as? [String: Any]
        else {
            return false
        }

        let teamIdentifier = signingInfo[kSecCodeInfoTeamIdentifier as String] as? String
        return teamIdentifier?.isEmpty == false
    }

    private func isSupportedInstallLocation(bundlePath: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        return normalizedPath == "/Applications/DefaultBrowserSwitcher.app"
            || normalizedPath.hasPrefix("/Applications/")
    }

    private func isXcodeDevelopmentRun(bundlePath: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        return normalizedPath.contains("/DerivedData/")
            || normalizedPath.contains("/Build/Products/")
    }
}

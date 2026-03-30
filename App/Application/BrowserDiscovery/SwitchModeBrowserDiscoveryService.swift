import Foundation

struct SwitchModeBrowserDiscoveryService: BrowserDiscoveryService, BrowserOptimisticSwitchVerifying {
    let snapshotService: any BrowserDiscoveryService
    let launchServicesDirectService: any BrowserDiscoveryService
    let systemPromptService: any BrowserDiscoveryService
    let settings: BrowserSwitchSettings

    func fetchSnapshot() async throws -> BrowserDiscoverySnapshot {
        try await snapshotService.fetchSnapshot()
    }

    func switchDefaultBrowser(
        to target: BrowserSwitchTarget,
        baselineSnapshot: BrowserDiscoverySnapshot?
    ) async -> BrowserSwitchResult {
        switch settings.switchMode {
        case .launchServicesDirect:
            return await launchServicesDirectService.switchDefaultBrowser(to: target, baselineSnapshot: baselineSnapshot)
        case .systemPrompt:
            return await systemPromptService.switchDefaultBrowser(to: target, baselineSnapshot: baselineSnapshot)
        }
    }

    func reconcileOptimisticSwitch(lastSwitchResult: BrowserSwitchResult) async -> BrowserOptimisticVerificationOutcome? {
        guard settings.switchMode == .launchServicesDirect,
              let verifier = launchServicesDirectService as? any BrowserOptimisticSwitchVerifying
        else {
            return nil
        }

        return await verifier.reconcileOptimisticSwitch(lastSwitchResult: lastSwitchResult)
    }
}

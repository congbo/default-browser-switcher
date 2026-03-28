import AppKit
import Combine
import Foundation

@MainActor
final class BrowserDiscoveryStore: ObservableObject {
    enum Phase: String, Codable {
        case idle
        case refreshing
        case loaded
        case failed
    }

    enum SwitchPhase: String, Codable {
        case idle
        case switching
        case success
        case mixed
        case failure
    }

    enum RetryAvailability: Equatable {
        enum DisabledReason: Equatable {
            case noPreviousTarget
            case missingSnapshot
            case targetMissing(displayName: String)
            case missingRequiredSchemes(targetName: String)
            case switchInProgress(targetName: String)
        }

        case enabled(targetName: String)
        case disabled(DisabledReason)
    }

    enum StoreError: LocalizedError {
        case missingSnapshot
        case missingRetryTarget
        case unknownCandidate(String)
        case retryTargetMissingFromSnapshot(String)
        case candidateMissingSupportedSchemes(String)
        case retryTargetMissingSupportedSchemes(String)
        case switchAlreadyInProgress

        var errorDescription: String? {
            switch self {
            case .missingSnapshot:
                return "No browser snapshot is loaded yet. Refresh discovery before switching."
            case .missingRetryTarget:
                return "No previous browser switch target is available to retry yet."
            case let .unknownCandidate(identifier):
                return "The requested browser is no longer present in the current snapshot: \(identifier)"
            case let .retryTargetMissingFromSnapshot(identifier):
                return "The last requested browser is no longer present in the current snapshot: \(identifier)"
            case let .candidateMissingSupportedSchemes(identifier):
                return "The requested browser does not support both http and https: \(identifier)"
            case let .retryTargetMissingSupportedSchemes(identifier):
                return "The last requested browser no longer supports both http and https: \(identifier)"
            case .switchAlreadyInProgress:
                return "A browser switch is already in progress. Wait for it to finish before retrying."
            }
        }
    }

    struct Report: Codable {
        let phase: Phase
        let switchPhase: SwitchPhase
        let lastRefreshAt: Date?
        let lastSwitchAt: Date?
        let lastErrorMessage: String?
        let snapshot: BrowserDiscoverySnapshot?
        let lastSwitchResult: BrowserSwitchResult?
    }

    typealias ReportWriter = (Report, URL) throws -> Void

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var switchPhase: SwitchPhase = .idle
    @Published private(set) var snapshot: BrowserDiscoverySnapshot?
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var lastSwitchAt: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastSwitchResult: BrowserSwitchResult?
    @Published private(set) var activeSwitchTarget: BrowserSwitchTarget?
    @Published private(set) var lastCoherentBrowser: BrowserApplication?
    @Published private(set) var successState: BrowserPresentation.SuccessState = .none
    @Published private(set) var prefersVerifiedPostSwitchPresentation = false
    @Published private(set) var retryAvailability: RetryAvailability = .disabled(.noPreviousTarget)

    private let service: BrowserDiscoveryService
    private let environment: [String: String]
    private let reportWriter: ReportWriter
    private let successResetScheduler: any BrowserPresentationSuccessResetScheduling
    private let successResetInterval: TimeInterval
    private let isEligibleSwitchTarget: (BrowserCandidate) -> Bool
    private var hasBootstrapped = false
    private var isSwitching = false
    private var successResetCancellable: AnyCancellable?

    init(
        service: BrowserDiscoveryService,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        reportWriter: @escaping ReportWriter = BrowserDiscoveryStore.writeReport(_:to:),
        successResetScheduler: any BrowserPresentationSuccessResetScheduling = BrowserPresentationSuccessResetScheduler(),
        successResetInterval: TimeInterval = 5,
        isEligibleSwitchTarget: @escaping (BrowserCandidate) -> Bool = { _ in true }
    ) {
        self.service = service
        self.environment = environment
        self.reportWriter = reportWriter
        self.successResetScheduler = successResetScheduler
        self.successResetInterval = successResetInterval
        self.isEligibleSwitchTarget = isEligibleSwitchTarget
        updateRetryAvailability()
    }

    var hasSnapshot: Bool {
        snapshot != nil
    }

    var presentation: BrowserPresentation {
        BrowserPresentation(
            snapshot: snapshot,
            lastSwitchResult: lastSwitchResult,
            lastCoherentBrowser: lastCoherentBrowser,
            preferVerifiedPostSwitch: prefersVerifiedPostSwitchPresentation,
            switchPhase: switchPhase,
            successState: successState,
            phase: phase,
            lastErrorMessage: lastErrorMessage,
            activeSwitchTarget: activeSwitchTarget,
            retryAvailability: retryAvailability,
            isEligibleSwitchTarget: isEligibleSwitchTarget
        )
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else {
            return
        }

        hasBootstrapped = true
        await refresh()
    }

    func refreshIfNeeded() async {
        guard snapshot == nil, phase != .refreshing else {
            return
        }

        await refresh()
    }

    func refresh() async {
        guard phase != .refreshing else {
            return
        }

        clearSuccessState()
        clearDerivedPostSwitchPresentation()
        phase = .refreshing
        updateRetryAvailability()

        do {
            let snapshot = try await service.fetchSnapshot()
            applyLiveSnapshot(snapshot)
            lastErrorMessage = nil
            phase = .loaded
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .failed
        }

        updateRetryAvailability()
        await persistReportIfRequested()
    }

    func switchToBrowser(matchingNormalizedApplicationPath applicationPath: String) async -> BrowserSwitchResult {
        let normalizedURL = URL(fileURLWithPath: applicationPath).standardizedFileURL
        clearSuccessState()
        clearDerivedPostSwitchPresentation()

        guard let currentSnapshot = snapshot else {
            let error = StoreError.missingSnapshot
            let result = makeStoreFailureResult(
                for: BrowserSwitchTarget(bundleIdentifier: nil, displayName: nil, applicationURL: normalizedURL),
                error: error
            )
            switchPhase = .failure
            lastSwitchResult = result
            lastSwitchAt = result.completedAt
            lastErrorMessage = error.errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        guard let candidate = currentSnapshot.candidate(matchingNormalizedApplicationPath: normalizedURL.path) else {
            let error = StoreError.unknownCandidate(normalizedURL.path)
            let result = makeStoreFailureResult(
                for: BrowserSwitchTarget(bundleIdentifier: nil, displayName: nil, applicationURL: normalizedURL),
                error: error
            )
            switchPhase = .failure
            lastSwitchResult = result
            lastSwitchAt = result.completedAt
            lastErrorMessage = error.errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        return await switchToBrowser(candidate)
    }

    func retryLastSwitchTarget() async -> BrowserSwitchResult {
        clearSuccessState()
        clearDerivedPostSwitchPresentation()

        if isSwitching {
            let target = activeSwitchTarget ?? lastSwitchResult?.requestedTarget ?? BrowserSwitchTarget(bundleIdentifier: nil, displayName: "Browser", applicationURL: URL(fileURLWithPath: "/Applications/Browser.app"))
            let result = makeStoreFailureResult(for: target, error: StoreError.switchAlreadyInProgress)
            lastErrorMessage = StoreError.switchAlreadyInProgress.errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        guard let requestedTarget = lastSwitchResult?.requestedTarget else {
            let target = BrowserSwitchTarget(bundleIdentifier: nil, displayName: "Browser", applicationURL: URL(fileURLWithPath: "/Applications/Browser.app"))
            let result = makeStoreFailureResult(for: target, error: StoreError.missingRetryTarget)
            switchPhase = .failure
            lastSwitchResult = result
            lastSwitchAt = result.completedAt
            lastErrorMessage = StoreError.missingRetryTarget.errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        guard let currentSnapshot = snapshot else {
            let result = makeStoreFailureResult(for: requestedTarget, error: StoreError.missingSnapshot)
            switchPhase = .failure
            lastSwitchResult = result
            lastSwitchAt = result.completedAt
            lastErrorMessage = StoreError.missingSnapshot.errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        guard let matchedCandidate = currentSnapshot.candidate(matchingNormalizedApplicationPath: requestedTarget.id) else {
            let error = StoreError.retryTargetMissingFromSnapshot(requestedTarget.id)
            let result = makeStoreFailureResult(for: requestedTarget, error: error)
            switchPhase = .failure
            lastSwitchResult = result
            lastSwitchAt = result.completedAt
            lastErrorMessage = error.errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        guard matchedCandidate.supportsRequiredSchemes else {
            let error = StoreError.retryTargetMissingSupportedSchemes(requestedTarget.id)
            let result = makeStoreFailureResult(for: requestedTarget, error: error)
            switchPhase = .failure
            lastSwitchResult = result
            lastSwitchAt = result.completedAt
            lastErrorMessage = error.errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        return await switchToBrowser(matchedCandidate)
    }

    func switchToBrowser(_ candidate: BrowserCandidate) async -> BrowserSwitchResult {
        if isSwitching {
            let result = makeStoreFailureResult(
                for: BrowserSwitchTarget(candidate: candidate),
                error: StoreError.switchAlreadyInProgress
            )
            lastErrorMessage = StoreError.switchAlreadyInProgress.errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        clearSuccessState()
        clearDerivedPostSwitchPresentation()

        guard let currentSnapshot = snapshot else {
            let result = makeStoreFailureResult(for: BrowserSwitchTarget(candidate: candidate), error: StoreError.missingSnapshot)
            switchPhase = .failure
            lastSwitchResult = result
            lastSwitchAt = result.completedAt
            lastErrorMessage = StoreError.missingSnapshot.errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        let target = BrowserSwitchTarget(candidate: candidate)

        guard let matchedCandidate = currentSnapshot.candidate(matchingNormalizedApplicationPath: target.id) else {
            let result = makeStoreFailureResult(for: target, error: StoreError.unknownCandidate(target.id))
            switchPhase = .failure
            lastSwitchResult = result
            lastSwitchAt = result.completedAt
            lastErrorMessage = StoreError.unknownCandidate(target.id).errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        guard matchedCandidate.supportsRequiredSchemes else {
            let result = makeStoreFailureResult(for: target, error: StoreError.candidateMissingSupportedSchemes(target.id))
            switchPhase = .failure
            lastSwitchResult = result
            lastSwitchAt = result.completedAt
            lastErrorMessage = StoreError.candidateMissingSupportedSchemes(target.id).errorDescription
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        if BrowserURLScheme.allCases.allSatisfy({ currentSnapshot.currentHandler(for: $0)?.normalizedApplicationPath == target.id }) {
            let result = BrowserSwitchResult(
                requestedTarget: target,
                schemeOutcomes: BrowserURLScheme.allCases.map(BrowserSwitchSchemeOutcome.skipped),
                verifiedSnapshot: currentSnapshot,
                readbackErrorMessage: nil,
                classification: .success,
                mismatchDetails: [],
                completedAt: .now
            )
            activeSwitchTarget = nil
            lastSwitchResult = result
            lastSwitchAt = result.completedAt
            switchPhase = .success
            lastErrorMessage = nil
            updateRetryAvailability()
            await persistReportIfRequested()
            return result
        }

        activeSwitchTarget = target
        isSwitching = true
        switchPhase = .switching
        lastErrorMessage = nil
        updateRetryAvailability()

        let result = await service.switchDefaultBrowser(to: target)

        isSwitching = false
        applySwitchResult(result)

        await persistReportIfRequested()
        return result
    }

    func currentHandler(for scheme: BrowserURLScheme) -> BrowserApplication? {
        snapshot?.currentHandler(for: scheme)
    }

    func makeReport() -> Report {
        Report(
            phase: phase,
            switchPhase: switchPhase,
            lastRefreshAt: lastRefreshAt,
            lastSwitchAt: lastSwitchAt,
            lastErrorMessage: lastErrorMessage,
            snapshot: snapshot,
            lastSwitchResult: lastSwitchResult
        )
    }

    private func mapSwitchPhase(for classification: BrowserSwitchResult.Classification) -> SwitchPhase {
        switch classification {
        case .success:
            .success
        case .mixed:
            .mixed
        case .failure:
            .failure
        }
    }

    private func makeStoreFailureResult(for target: BrowserSwitchTarget, error: Error) -> BrowserSwitchResult {
        BrowserSwitchResult.serviceFailure(
            target: target,
            schemeOutcomes: BrowserURLScheme.allCases.map { .failure($0, message: error.localizedDescription) },
            readbackErrorMessage: error.localizedDescription,
            completedAt: .now
        )
    }

    private func applyLiveSnapshot(_ snapshot: BrowserDiscoverySnapshot) {
        self.snapshot = snapshot
        lastRefreshAt = snapshot.refreshedAt

        if let coherentCurrentBrowser = snapshot.coherentCurrentBrowser {
            lastCoherentBrowser = coherentCurrentBrowser
        }

        updateRetryAvailability()
    }

    private func applySwitchResult(_ result: BrowserSwitchResult) {
        activeSwitchTarget = nil
        lastSwitchResult = result
        lastSwitchAt = result.completedAt
        switchPhase = mapSwitchPhase(for: result.classification)
        lastErrorMessage = result.visibleErrorMessage

        if let coherentVerifiedBrowser = result.verifiedSnapshot?.coherentCurrentBrowser {
            lastCoherentBrowser = coherentVerifiedBrowser
        }

        prefersVerifiedPostSwitchPresentation = result.classification != .success && result.verifiedSnapshot?.coherentCurrentBrowser != nil

        if result.classification == .success, let verifiedSnapshot = result.verifiedSnapshot {
            applyLiveSnapshot(verifiedSnapshot)
            phase = .loaded
            setSuccessState(.updated(browserName: result.requestedTarget.displayName))
        }

        updateRetryAvailability()
    }

    private func clearDerivedPostSwitchPresentation() {
        activeSwitchTarget = nil
        prefersVerifiedPostSwitchPresentation = false
        updateRetryAvailability()
    }

    private func setSuccessState(_ successState: BrowserPresentation.SuccessState) {
        successResetCancellable?.cancel()
        successResetCancellable = nil
        self.successState = successState

        guard case .updated = successState else {
            return
        }

        successResetCancellable = successResetScheduler.schedule(after: successResetInterval) { [weak self] in
            self?.successState = .none
            self?.successResetCancellable = nil
        }
    }

    private func clearSuccessState() {
        setSuccessState(.none)
    }

    private func updateRetryAvailability() {
        retryAvailability = resolveRetryAvailability()
    }

    private func resolveRetryAvailability() -> RetryAvailability {
        if isSwitching || switchPhase == .switching {
            let targetName = activeSwitchTarget?.displayName ?? lastSwitchResult?.requestedTarget.displayName ?? "Browser"
            return .disabled(.switchInProgress(targetName: targetName))
        }

        if lastSwitchResult?.readbackErrorMessage == StoreError.missingRetryTarget.localizedDescription {
            return .disabled(.noPreviousTarget)
        }

        guard let requestedTarget = lastSwitchResult?.requestedTarget else {
            return .disabled(.noPreviousTarget)
        }

        guard let currentSnapshot = snapshot else {
            return .disabled(.missingSnapshot)
        }

        guard let candidate = currentSnapshot.candidate(matchingNormalizedApplicationPath: requestedTarget.id) else {
            return .disabled(.targetMissing(displayName: requestedTarget.displayName))
        }

        guard candidate.supportsRequiredSchemes else {
            return .disabled(.missingRequiredSchemes(targetName: requestedTarget.displayName))
        }

        return .enabled(targetName: candidate.resolvedDisplayName)
    }

    private func persistReportIfRequested() async {
        guard let outputPath = environment["DEFAULT_BROWSER_SWITCHER_SNAPSHOT_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !outputPath.isEmpty
        else {
            return
        }

        let outputURL = URL(fileURLWithPath: outputPath)

        do {
            try reportWriter(makeReport(), outputURL)
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        if let exitAfterSnapshot = environment["DEFAULT_BROWSER_SWITCHER_EXIT_AFTER_SNAPSHOT"], exitAfterSnapshot != "0" {
            NSApplication.shared.terminate(nil)
        }
    }

    nonisolated private static func writeReport(_ report: Report, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }
}

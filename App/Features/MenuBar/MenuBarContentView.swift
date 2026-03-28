import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var store: BrowserDiscoveryStore
    @EnvironmentObject private var iconProvider: BrowserIconProvider

    private var presentation: BrowserPresentation {
        store.presentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let statusText = presentation.statusMessageText {
                Text(verbatim: statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            candidateSection

            if presentation.showRefreshInMenu {
                Divider()

                Button(String(localized: "menu.refresh")) {
                    Task {
                        await store.refresh()
                    }
                }
                .disabled(store.phase == .refreshing || store.switchPhase == .switching)
            }

            Divider()

            Button(DefaultBrowserSwitcherApp.settingsTitle) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            Button(String(localized: "menu.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(minWidth: 300)
        .task {
            await store.bootstrapIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let currentBrowser = presentation.currentBrowser {
                Image(nsImage: iconProvider.icon(for: currentBrowser.application))
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(.rect(cornerRadius: 4))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Default browser")
                        .font(.headline)
                    Text(verbatim: currentBrowser.application.resolvedDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Default browser")
                    .font(.headline)
            }
        }
    }

    @ViewBuilder
    private var candidateSection: some View {
        if presentation.pickerBrowsers.isEmpty {
            Text(presentation.settingsPickerPlaceholder)
                .foregroundStyle(.secondary)
        } else {
            ForEach(presentation.pickerBrowsers) { row in
                if row.actionState == .switchable {
                    Button {
                        Task {
                            await store.switchToBrowser(row.candidate)
                        }
                    } label: {
                        BrowserMenuRow(row: row)
                            .environmentObject(iconProvider)
                    }
                    .buttonStyle(.plain)
                } else {
                    BrowserMenuRow(row: row)
                        .environmentObject(iconProvider)
                }
            }
        }
    }
}

private struct BrowserMenuRow: View {
    @EnvironmentObject private var iconProvider: BrowserIconProvider

    let row: BrowserPresentation.Candidate

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if row.actionState == .currentSelection {
                    Image(systemName: "checkmark")
                } else {
                    Color.clear
                }
            }
            .frame(width: 12, height: 12)
            .foregroundStyle(Color.accentColor)

            Image(nsImage: iconProvider.icon(for: row.candidate))
                .resizable()
                .frame(width: 16, height: 16)
                .clipShape(.rect(cornerRadius: 4))
                .accessibilityHidden(true)

            Text(verbatim: row.candidate.resolvedDisplayName)
                .foregroundStyle(row.actionState == .disabled(.switchInProgress) ? .secondary : .primary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

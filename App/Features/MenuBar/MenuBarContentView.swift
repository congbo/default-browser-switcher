import AppKit
import SwiftUI

struct MenuBarContentView: View {
    fileprivate enum Layout {
        static let menuIconSize: CGFloat = 32
        static let menuIconCornerRadius: CGFloat = 7
    }

    @EnvironmentObject private var store: BrowserDiscoveryStore
    @EnvironmentObject private var iconProvider: BrowserIconProvider

    private var presentation: BrowserPresentation {
        store.presentation
    }

    var body: some View {
        Group {
            candidateSection

            Divider()

            aboutButton

            Divider()

            Button(String(localized: "menu.refresh")) {
                Task {
                    await store.refresh()
                }
            }
            .disabled(store.phase == .refreshing || store.switchPhase == .switching)

            Button(String(localized: "menu.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .task {
            await store.bootstrapIfNeeded()
        }
    }

    @ViewBuilder
    private var candidateSection: some View {
        if presentation.pickerBrowsers.isEmpty {
            Text(presentation.settingsPickerPlaceholder)
                .disabled(true)
        } else {
            ForEach(presentation.pickerBrowsers) { row in
                Toggle(isOn: selectionBinding(for: row)) {
                    BrowserMenuRow(row: row)
                        .environmentObject(iconProvider)
                }
                .disabled(row.actionState != .switchable)
            }
        }
    }

    private var aboutButton: some View {
        Button(StandardAboutPanelConfiguration.menuTitle) {
            StandardAboutPanelConfiguration.present()
        }
    }

    private func selectionBinding(for row: BrowserPresentation.Candidate) -> Binding<Bool> {
        Binding(
            get: { row.actionState == .currentSelection },
            set: { isSelected in
                guard isSelected, row.actionState == .switchable else {
                    return
                }

                Task {
                    await store.switchToBrowser(row.candidate)
                }
            }
        )
    }
}

struct StandardAboutPanelConfiguration {
    static let menuTitle = "About"
    static let projectURL = URL(string: "https://github.com/congbo/default-browser-switcher")!

    @MainActor
    static func present() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options())
    }

    static func options(applicationName: String = applicationName()) -> [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: applicationName,
            .credits: credits()
        ]
    }

    static func credits(projectURL: URL = projectURL) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let urlString = projectURL.absoluteString
        let attributedString = NSMutableAttributedString(
            string: urlString,
            attributes: [
                .paragraphStyle: paragraphStyle
            ]
        )
        let urlRange = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
        attributedString.addAttributes(
            [
                .link: projectURL,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ],
            range: urlRange
        )
        return attributedString
    }

    static func applicationName(bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
            ?? ProcessInfo.processInfo.processName
    }
}

struct BrowserAppIconView: View {
    let image: NSImage
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct BrowserMenuRow: View {
    @EnvironmentObject private var iconProvider: BrowserIconProvider

    let row: BrowserPresentation.Candidate

    var body: some View {
        Label {
            Text(verbatim: row.candidate.resolvedDisplayName)
        } icon: {
            BrowserAppIconView(
                image: iconProvider.icon(for: row.candidate, size: MenuBarContentView.Layout.menuIconSize),
                size: MenuBarContentView.Layout.menuIconSize,
                cornerRadius: MenuBarContentView.Layout.menuIconCornerRadius
            )
        }
        .foregroundStyle(row.actionState == .disabled(.switchInProgress) ? .secondary : .primary)
    }
}

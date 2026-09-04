import AppKit
import Domain
import SwiftUI

enum AppLanguagePreferences {
    static let key = "appLanguage"

    static func initialIdentifier(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        SupportedAppLanguage.resolve(
            storedIdentifier: defaults.string(forKey: key),
            preferredLanguages: preferredLanguages
        ).rawValue
    }

    static func persist(_ identifier: String, defaults: UserDefaults = .standard) {
        defaults.set(identifier, forKey: key)
    }
}

func localizedAppString(_ value: String.LocalizationValue, locale: Locale) -> String {
    String(localized: value, locale: locale)
}

@main
struct TokenWatchMacApp: App {
    @State private var store = MacHubStore()
    @StateObject private var updateController = MacUpdateController()
    @State private var languageIdentifier: String
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _languageIdentifier = State(
            initialValue: AppLanguagePreferences.initialIdentifier()
        )
    }

    private var selectedLanguage: SupportedAppLanguage {
        SupportedAppLanguage(rawValue: languageIdentifier) ?? .systemDefault
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { languageIdentifier },
            set: { identifier in
                languageIdentifier = identifier
                AppLanguagePreferences.persist(identifier)
            }
        )
    }

    var body: some Scene {
        WindowGroup("TokenWatch", id: "dashboard") {
            MacHubView(
                store: store,
                updateController: updateController,
                languageIdentifier: languageBinding
            )
                .frame(minWidth: 980, minHeight: 680)
                .overlay(alignment: .topTrailing) {
                    UpdateAvailableBanner(updateController: updateController)
                        .padding(16)
                }
                .onAppear {
                    updateController.dashboardDidAppear()
                }
                .environment(\.locale, selectedLanguage.locale)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshAfterActivation()
                        updateController.dashboardDidAppear()
                    }
                }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarDashboardView(store: store, updateController: updateController)
                .environment(\.locale, selectedLanguage.locale)
        } label: {
            Image(
                nsImage: MenuBarStatusImageRenderer.make(
                    today: todayValue,
                    todayLabel: localizedAppString("今天", locale: selectedLanguage.locale),
                    remaining: remainingValue,
                    remainingLabel: localizedAppString("剩余", locale: selectedLanguage.locale)
                )
            )
            .renderingMode(.original)
            .accessibilityLabel(
                Text(verbatim: "\(localizedAppString("今天", locale: selectedLanguage.locale)) \(todayValue), \(localizedAppString("剩余", locale: selectedLanguage.locale)) \(remainingValue)")
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView(
                store: store,
                updateController: updateController,
                languageIdentifier: languageBinding
            )
                .frame(width: 560, height: 520)
                .preferredColorScheme(.dark)
                .environment(\.locale, selectedLanguage.locale)
        }
    }

    private var todayValue: String {
        store.snapshot.hasKnownUsage(for: .today)
            ? UsageFormatting.compactTokens(
                    store.snapshot.totalTokens(for: .today),
                    estimated: store.snapshot.hasEstimatedUsage(for: .today)
                )
            : "—"
    }

    private var remainingValue: String {
        guard let remaining = store.snapshot.providers
            .first(where: { !$0.windows.isEmpty })?
            .windows.first?
            .remainingPercent
        else {
            return "—"
        }
        return "\(Int(remaining.rounded()))%"
    }
}

@MainActor
private enum MenuBarStatusImageRenderer {
    private struct CacheKey: Hashable {
        let today: String
        let todayLabel: String
        let remaining: String
        let remainingLabel: String
        let appearance: String
    }

    private static let height: CGFloat = 22
    private static var imageCache: [CacheKey: NSImage] = [:]

    static func make(
        today: String,
        todayLabel: String,
        remaining: String,
        remainingLabel: String
    ) -> NSImage {
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? ""
        let key = CacheKey(
            today: today,
            todayLabel: todayLabel,
            remaining: remaining,
            remainingLabel: remainingLabel,
            appearance: appearance
        )
        if let cached = imageCache[key] { return cached }

        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let labelFont = NSFont.systemFont(ofSize: 7, weight: .regular)
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let columns = [
            makeColumn(value: today, label: todayLabel, valueAttributes: valueAttributes, labelAttributes: labelAttributes),
            makeColumn(value: remaining, label: remainingLabel, valueAttributes: valueAttributes, labelAttributes: labelAttributes),
        ]

        let separatorGap: CGFloat = 4
        let separatorWidth: CGFloat = 0.5
        let horizontalPadding: CGFloat = 3
        let columnsWidth = columns.reduce(CGFloat(0)) { $0 + $1.width }
            + separatorGap * 2
            + separatorWidth
        let imageWidth = ceil(horizontalPadding * 2 + columnsWidth)

        let image = NSImage(size: NSSize(width: imageWidth, height: height), flipped: false) { _ in
            let valueHeight = ceil(valueFont.ascender - valueFont.descender)
            let labelHeight = ceil(labelFont.ascender - labelFont.descender)
            let lineGap: CGFloat = -1
            let blockHeight = valueHeight + lineGap + labelHeight
            let labelY = floor((height - blockHeight) / 2)
            let valueY = labelY + labelHeight + lineGap
            var cursorX = horizontalPadding

            for (index, column) in columns.enumerated() {
                if index > 0 {
                    let separatorX = cursorX + separatorGap
                    NSColor.labelColor.withAlphaComponent(0.5).setFill()
                    NSRect(
                        x: separatorX,
                        y: labelY + 1,
                        width: separatorWidth,
                        height: blockHeight - 2
                    ).fill()
                    cursorX = separatorX + separatorWidth + separatorGap
                }

                let valueRect = NSRect(
                    x: cursorX,
                    y: valueY,
                    width: column.width,
                    height: valueHeight
                )
                let labelRect = NSRect(
                    x: cursorX,
                    y: labelY,
                    width: column.width,
                    height: labelHeight
                )
                column.value.draw(in: centeredRect(for: column.value, in: valueRect))
                column.label.draw(in: centeredRect(for: column.label, in: labelRect))
                cursorX += column.width
            }
            return true
        }
        image.isTemplate = false
        if imageCache.count >= 16 { imageCache.removeAll(keepingCapacity: true) }
        imageCache[key] = image
        return image
    }

    private static func makeColumn(
        value: String,
        label: String,
        valueAttributes: [NSAttributedString.Key: Any],
        labelAttributes: [NSAttributedString.Key: Any]
    ) -> (value: NSAttributedString, label: NSAttributedString, width: CGFloat) {
        let valueText = NSAttributedString(string: value, attributes: valueAttributes)
        let labelText = NSAttributedString(string: label, attributes: labelAttributes)
        let width = ceil(max(30, valueText.size().width, labelText.size().width))
        return (valueText, labelText, width)
    }

    private static func centeredRect(
        for text: NSAttributedString,
        in bounds: NSRect
    ) -> NSRect {
        NSRect(
            x: bounds.midX - text.size().width / 2,
            y: bounds.minY,
            width: text.size().width,
            height: bounds.height
        )
    }

}

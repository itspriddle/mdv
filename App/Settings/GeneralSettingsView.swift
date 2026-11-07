import MdvCore
import SwiftUI

/// Settings > General (#36). Each control reads `SettingsModel` and changes the setting through
/// its `set…` method; the identifiers (`settings-*`) are for UI tests.
///
/// Sections: Themes (the default theme, custom theme files that didn't load, and Open Themes
/// Folder, #35), Windows (outline default), Reading (zoom and content width, which apply
/// to every window at once, as View > Zoom and View > Content Width do), and Default Viewer.
struct GeneralSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Default theme:", selection: binding(\.defaultThemeID, model.setDefaultTheme(id:))) {
                    ForEach(Array(model.themeSections.enumerated()), id: \.offset) { index, section in
                        if index > 0 {
                            Divider()
                        }
                        ForEach(section, id: \.id) { theme in
                            Text(theme.displayName).tag(theme.id)
                        }
                    }
                }
                .accessibilityIdentifier("settings-default-theme")
                note("New windows open in this theme. View > Theme changes a window’s theme.")
                ForEach(model.themeFailures, id: \.self) { failure in
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Not loaded: \(failure)")
                }
                if model.canOpenThemesFolder {
                    LabeledContent("Custom themes:") {
                        Button("Open Themes Folder") { model.openThemesFolder() }
                            .accessibilityIdentifier("settings-open-themes-folder")
                    }
                }
            }

            Section {
                Toggle(
                    "Show the outline in new windows",
                    isOn: binding(\.showsOutlineInNewWindows, model.setShowsOutlineInNewWindows)
                )
                .accessibilityIdentifier("settings-outline")
            }

            Section {
                Picker("Zoom:", selection: binding(\.zoomLevel, model.setZoomLevel)) {
                    ForEach(PageZoom.levels, id: \.self) { level in
                        Text(SettingsModel.zoomTitle(level)).tag(level)
                    }
                }
                .accessibilityIdentifier("settings-zoom")
                Picker("Content width:", selection: binding(\.contentWidth, model.setContentWidth)) {
                    ForEach(ContentWidth.allCases, id: \.self) { width in
                        Text(width.displayName).tag(width)
                    }
                }
                .accessibilityIdentifier("settings-content-width")
                note("Zoom and content width apply to every window.")
            }

            Section {
                LabeledContent("Default viewer:") {
                    if model.isDefaultViewer {
                        Text("mdv opens Markdown files")
                            .accessibilityIdentifier("settings-default-viewer-status")
                    } else {
                        Button("Make mdv the Default Markdown Viewer") {
                            Task { await model.makeDefaultViewer() }
                        }
                        .disabled(model.isMakingDefaultViewer)
                        .accessibilityIdentifier("settings-default-viewer")
                    }
                }
            }
        }
        .formStyle(.columns)
        .padding(20)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A binding that reads the model's property and changes it through `set`.
    private func binding<Value>(
        _ keyPath: KeyPath<SettingsModel, Value>, _ set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: { model[keyPath: keyPath] }, set: set)
    }

    /// Secondary text under a control.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

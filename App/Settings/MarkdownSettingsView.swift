import MdvCore
import SwiftUI

/// Settings > Markdown (#55): how documents are read. Each control reads `SettingsModel` and
/// changes the setting through its `set…` method; the identifiers (`settings-*`) are for UI
/// tests. Every setting here applies to open documents at once (they render again in place,
/// keeping the reading position).
///
/// Sections, in reading (and VoiceOver) order:
/// - Flavor: the default flavor, from `FlavorRegistry`.
/// - Frontmatter: hidden or shown as a table.
/// - Built-in preprocessors: one toggle per `MarkdownSettings.optionalPreprocessors` entry
///   (wiki links, #53), with its note; hidden while the list is empty.
/// - (Custom preprocessor, #57: its own section goes last, below the built-in ones.)
struct MarkdownSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Default flavor:", selection: binding(\.defaultFlavorID, model.setDefaultFlavor(id:))) {
                    ForEach(model.flavors) { flavor in
                        Text(flavor.displayName).tag(flavor.id)
                    }
                }
                .accessibilityIdentifier("settings-default-flavor")
                note("How documents are parsed. Open documents update right away.")
            }

            Section {
                Picker("Frontmatter:", selection: binding(\.frontmatterDisplay, model.setFrontmatterDisplay)) {
                    ForEach(FrontmatterDisplay.allCases, id: \.self) { display in
                        Text(display.settingsTitle).tag(display)
                    }
                }
                .accessibilityIdentifier("settings-frontmatter")
                note("YAML or TOML at the top of a file. Shown as a table above the document, or hidden.")
            }

            if !model.optionalPreprocessors.isEmpty {
                Section("Built-in preprocessors") {
                    ForEach(model.optionalPreprocessors, id: \.self) { preprocessor in
                        Toggle(preprocessor.settingsTitle, isOn: preprocessorBinding(preprocessor))
                            .accessibilityIdentifier("settings-preprocessor-\(preprocessor.rawValue)")
                        note(preprocessor.settingsNote)
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

    private func preprocessorBinding(_ preprocessor: MarkdownTransform) -> Binding<Bool> {
        Binding(
            get: { model.builtInPreprocessors.contains(preprocessor) },
            set: { model.setBuiltInPreprocessor(preprocessor, isOn: $0) })
    }

    /// Secondary text under a control.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension FrontmatterDisplay {
    /// The Frontmatter picker's title.
    var settingsTitle: String {
        switch self {
        case .hidden: "Hidden"
        case .table: "Shown as a Table"
        }
    }
}

extension MarkdownTransform {
    /// The toggle's title in Settings > Markdown > Built-in preprocessors. Only
    /// `MarkdownSettings.optionalPreprocessors` are listed; flavor-owned transforms have titles
    /// so the switch stays exhaustive.
    var settingsTitle: String {
        switch self {
        case .emojiShortcodes: "Emoji shortcodes"
        }
    }

    /// The note under the toggle.
    var settingsNote: String {
        switch self {
        case .emojiShortcodes: "Turns :tada: into 🎉. Part of GitHub Flavored Markdown."
        }
    }
}

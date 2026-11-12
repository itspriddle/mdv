import PeepCore
import SwiftUI

/// Settings > Markdown > Custom preprocessor (#57), the pane's last section: the on/off toggle
/// (behind a warning), the program (chosen with an Open panel, never typed), its arguments as a
/// list, the last run in this session, and Reset. Identifiers (`settings-custom-preprocessor*`)
/// are for UI tests.
struct CustomPreprocessorSection: View {
    @Bindable var model: CustomPreprocessorModel

    var body: some View {
        Section("Custom preprocessor") {
            Toggle(
                "Run a custom preprocessor",
                isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) })
            )
            .disabled(model.executablePath == nil)
            .accessibilityIdentifier("settings-custom-preprocessor")
            note(
                "Runs a program on every document before it's rendered: the document on standard input, "
                    + "Markdown on standard output. Choose a program first.")

            LabeledContent("Program:") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: model.executablePath ?? "None")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(model.executablePath == nil ? .secondary : .primary)
                            .help(model.executablePath ?? "")
                            .accessibilityIdentifier("settings-custom-preprocessor-path")
                        Button("Choose…") {
                            Task { await model.chooseExecutable() }
                        }
                        .accessibilityIdentifier("settings-custom-preprocessor-choose")
                    }
                    if let problem = model.rejectedChoice ?? model.executableProblem {
                        Text(verbatim: problem)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings-custom-preprocessor-problem")
                    }
                }
            }

            LabeledContent("Arguments:") {
                ArgumentListEditor(arguments: model.arguments, commit: model.setArguments)
            }

            LabeledContent("Last run:") {
                Text(verbatim: lastRunText)
                    .foregroundStyle(model.lastRun?.error == nil ? .secondary : .primary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings-custom-preprocessor-last-run")
            }

            Button("Reset") {
                model.reset()
            }
            .disabled(model.executablePath == nil && model.arguments.isEmpty && !model.isEnabled)
            .accessibilityIdentifier("settings-custom-preprocessor-reset")
        }
        .alert("Run a program on every document?", isPresented: $model.isConfirmingEnable) {
            Button("Turn On") { model.confirmEnable() }
                .accessibilityIdentifier("settings-custom-preprocessor-confirm")
            Button("Cancel", role: .cancel) { model.cancelEnable() }
        } message: {
            Text(verbatim: warning)
        }
    }

    /// The warning before turning the preprocessor on.
    private var warning: String {
        let name = model.executableName.map { "“\($0)”" } ?? "the program"
        return "Peep will run \(name) on every document you open, as you, with access to everything you can "
            + "access. Each document's text is sent to it. Documents can't turn it on or choose another program. "
            + "Only turn this on for a program you trust."
    }

    private var lastRunText: String {
        guard let run = model.lastRun else {
            return "None yet."
        }
        let time = run.date.formatted(date: .omitted, time: .standard)
        guard let error = run.error else {
            return "Succeeded on \(run.documentName) at \(time)."
        }
        return "Failed on \(run.documentName) at \(time): \(error.message)"
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The preprocessor's arguments, one field each, passed verbatim (no shell, no splitting).
/// Edits are committed on Return and when a field loses focus, so a half-typed argument
/// doesn't re-render every open document on each keystroke; empty fields are dropped.
private struct ArgumentListEditor: View {
    let arguments: [String]
    let commit: ([String]) -> Void

    private struct Row: Identifiable {
        let id = UUID()
        var text: String
    }

    @State private var rows: [Row] = []
    @FocusState private var focusedRow: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($rows) { $row in
                let index = rows.firstIndex { $0.id == row.id } ?? 0
                HStack(spacing: 4) {
                    TextField("Argument \(index + 1)", text: $row.text)
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedRow, equals: row.id)
                        .onSubmit(commitRows)
                        .accessibilityIdentifier("settings-custom-preprocessor-argument-\(index + 1)")
                    Button {
                        rows.removeAll { $0.id == row.id }
                        commitRows()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this argument")
                    .accessibilityLabel("Remove argument \(index + 1)")
                }
            }
            Button("Add Argument") {
                let row = Row(text: "")
                rows.append(row)
                focusedRow = row.id
            }
            .accessibilityIdentifier("settings-custom-preprocessor-add-argument")
        }
        .onAppear { rows = arguments.map { Row(text: $0) } }
        .onChange(of: arguments) { _, newValue in
            // A change from elsewhere (Reset); the editor's own commits already match.
            if CustomPreprocessorModel.committed(rows.map(\.text)) != newValue {
                rows = newValue.map { Row(text: $0) }
            }
        }
        .onChange(of: focusedRow) { commitRows() }
        .onDisappear(perform: commitRows)
    }

    private func commitRows() {
        commit(rows.map(\.text))
    }
}

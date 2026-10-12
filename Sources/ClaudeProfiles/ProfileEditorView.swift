import SwiftUI
import ClaudeProfilesCore

/// Create or edit a profile: a name, a color, and a live preview of the badge.
struct ProfileEditorView: View {
    enum Mode {
        case create
        case edit(Profile)
    }

    let mode: Mode
    let onSave: (String, ProfileColor) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var color: ProfileColor
    @FocusState private var nameFocused: Bool

    init(
        mode: Mode,
        initialName: String? = nil,
        onSave: @escaping (String, ProfileColor) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .create:
            _name = State(initialValue: initialName ?? "")
            _color = State(initialValue: ProfileColor.automatic(for: initialName ?? UUID().uuidString))
        case .edit(let profile):
            _name = State(initialValue: profile.name)
            _color = State(initialValue: profile.color)
        }
    }

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { ProfileSlug.make(from: trimmedName) != nil }
    private var initial: String { trimmedName.first.map { String($0).uppercased() } ?? "?" }

    var body: some View {
        VStack(spacing: 20) {
            BadgeView(initial: initial, color: color, size: 64)
                .animation(.snappy, value: color)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", text: $name, prompt: Text(isCreate ? "Work" : "Name"))
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit { if isValid { onSave(trimmedName, color) } }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(ProfileColor.allCases, id: \.self) { candidate in
                        ColorSwatch(color: candidate, isSelected: candidate == color) {
                            color = candidate
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isCreate {
                Text("A fresh Claude window opens so you can sign in to the account for this profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isCreate ? "Create & Open" : "Save") { onSave(trimmedName, color) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onAppear { nameFocused = true }
    }
}

private struct ColorSwatch: View {
    let color: ProfileColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color.gradient)
                .frame(width: 22, height: 22)
                .overlay {
                    Circle()
                        .strokeBorder(.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                        .padding(-4)
                }
                .animation(.snappy(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .help(color.label)
        .accessibilityLabel(color.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

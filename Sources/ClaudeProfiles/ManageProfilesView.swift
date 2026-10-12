import SwiftUI
import ClaudeProfilesCore

/// The management window: every profile with its state, plus rename, recolor, reveal, quit, delete.
struct ManageProfilesView: View {
    @ObservedObject var model: ProfilesModel
    let windows: WindowManager
    @State private var pendingDelete: Profile?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        isRunning: model.isRunning(profile),
                        model: model,
                        windows: windows,
                        onDelete: { pendingDelete = profile }
                    )
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Button {
                    windows.showEditor(.create)
                } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .keyboardShortcut("n")
                Spacer()
                Text("Profiles are folders in ~/Library/Application Support")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 500, minHeight: 320)
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { profile in
            Button("Move to Trash", role: .destructive) { model.trash(profile) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The profile's folder moves to the Trash, which signs that account out on this Mac. You can restore it from the Trash.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let isRunning: Bool
    let model: ProfilesModel
    let windows: WindowManager
    let onDelete: () -> Void

    /// The folder name is enough here; the footer says where the folders live and
    /// "Show in Finder" is one click away.
    private var subtitle: String {
        guard let directory = profile.dataDirectory else { return "Claude's own data folder" }
        return profile.hasOwnDockIcon ? "\(directory.lastPathComponent) · own Dock icon" : directory.lastPathComponent
    }

    var body: some View {
        HStack(spacing: 12) {
            BadgeView(initial: profile.initial, color: profile.color, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if isRunning {
                HStack(spacing: 5) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("Running")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(isRunning ? "Show" : "Open") { model.open(profile) }
                .controlSize(.small)

            Menu {
                Button("Rename…") { windows.showEditor(.edit(profile)) }
                Menu("Color") {
                    ForEach(ProfileColor.allCases, id: \.self) { candidate in
                        Toggle(candidate.label, isOn: Binding(
                            get: { profile.color == candidate },
                            set: { if $0 { model.setColor(candidate, for: profile) } }
                        ))
                    }
                }
                if !profile.isDefault {
                    Toggle("Separate Dock Icon", isOn: Binding(
                        get: { profile.hasOwnDockIcon },
                        set: { model.setOwnDockIcon($0, for: profile) }
                    ))
                }
                Divider()
                if !profile.isDefault {
                    Button("Show in Finder") { model.reveal(profile) }
                }
                if isRunning {
                    Button("Quit Claude") { model.quit(profile) }
                }
                if !profile.isDefault {
                    Divider()
                    Button("Delete…", role: .destructive, action: onDelete)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 6)
    }
}

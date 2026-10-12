import Foundation

/// Turns a display name into a safe folder-name suffix: `"Work (ACME)"` → `"Work-ACME"`.
public enum ProfileSlug {
    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))

    /// Returns `nil` when nothing usable is left after cleaning.
    public static func make(from name: String) -> String? {
        var out = ""
        var pendingDash = false
        for scalar in name.unicodeScalars {
            if allowed.contains(scalar) {
                if pendingDash, !out.isEmpty { out.append("-") }
                pendingDash = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Best-effort display name for a folder that has no stored metadata: `"Work-ACME"` → `"Work ACME"`.
    public static func displayName(fromFolderSuffix suffix: String) -> String {
        suffix.replacingOccurrences(of: "-", with: " ")
    }
}

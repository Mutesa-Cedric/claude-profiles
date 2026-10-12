import AppKit
import SwiftUI
import ClaudeProfilesCore

extension ProfileColor {
    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .graphite: return .systemGray
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    var label: String { rawValue.capitalized }
}

/// The colored disc with an initial that identifies a profile everywhere in the app.
enum ProfileBadge {
    /// AppKit version for menu rows.
    static func image(for profile: Profile, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            profile.color.nsColor.setFill()
            NSBezierPath(ovalIn: rect).fill()

            let base = NSFont.systemFont(ofSize: size * 0.56, weight: .semibold)
            let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: base.pointSize) }
            let text = NSAttributedString(string: profile.initial, attributes: [
                .font: rounded ?? base,
                .foregroundColor: NSColor.white,
            ])
            let textSize = text.size()
            text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// SwiftUI version for windows.
struct BadgeView: View {
    let initial: String
    let color: ProfileColor
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(color.color.gradient)
            Text(initial)
                .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

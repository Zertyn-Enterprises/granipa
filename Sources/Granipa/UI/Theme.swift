import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    static let bg = Color(hex: 0x161412)
    static let bgSidebar = Color(hex: 0x1C1A18)
    static let card = Color(hex: 0x232120)
    static let border = Color.white.opacity(0.07)
    static let accent = Color(hex: 0xF05423)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.34)

    static let titleFont = Font.system(size: 30, weight: .semibold, design: .serif)
    static let meetingTitleFont = Font.system(size: 24, weight: .semibold, design: .serif)

    private static let avatarPalette: [Color] = [
        Color(hex: 0x8A6D3B), Color(hex: 0xA85B32), Color(hex: 0x5B7A6A),
        Color(hex: 0x6B5B95), Color(hex: 0x3F6F8A), Color(hex: 0x9A4F4F),
    ]

    static func avatarColor(for key: String) -> Color {
        let hash = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return avatarPalette[hash % avatarPalette.count]
    }

    static func dayHeader(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.border, lineWidth: 1))
    }
}

extension View {
    func card(cornerRadius: CGFloat = 12) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }
}

struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(
                hovering ? Color.white.opacity(0.05) : .clear,
                in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}

struct AvatarView: View {
    let letterSource: String?
    var fallbackIcon = "doc.text"
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24)
            .fill(
                letterSource.map { Theme.avatarColor(for: $0).opacity(0.85) }
                    ?? Color.white.opacity(0.08))
            .frame(width: size, height: size)
            .overlay {
                if let source = letterSource, let first = source.first {
                    Text(String(first).uppercased())
                        .font(.system(size: size * 0.48, weight: .semibold, design: .serif))
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
    }
}

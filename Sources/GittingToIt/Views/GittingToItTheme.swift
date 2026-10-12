import SwiftUI

enum GTTheme {
    static let paper = Color(red: 0.985, green: 0.978, blue: 0.957)
    static let ink = Color(red: 0.055, green: 0.055, blue: 0.065)
    static let blue = Color(red: 0.25, green: 0.53, blue: 0.91)
    static let violet = Color(red: 0.84, green: 0.34, blue: 0.88)
    static let mint = Color(red: 0.02, green: 0.80, blue: 0.57)
    static let yellow = Color(red: 0.97, green: 0.91, blue: 0.18)
    static let blush = Color(red: 0.98, green: 0.92, blue: 0.93)
    static let gray = Color(red: 0.42, green: 0.42, blue: 0.44)

    static func repositoryColor(for id: UUID) -> Color {
        let palette = [blue, mint, violet, yellow]
        let stableValue = id.uuidString.utf8.reduce(0) { partial, byte in
            (partial &* 31 &+ Int(byte)) & 0x7fffffff
        }
        let index = stableValue % palette.count
        return palette[index]
    }
}

struct GTActionButtonStyle: ButtonStyle {
    var color: Color = GTTheme.paper

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.bold))
            .foregroundStyle(GTTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? color.opacity(0.65) : color)
            .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
            .contentShape(Rectangle())
    }
}

struct GTPanelModifier: ViewModifier {
    var fill: Color

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(fill)
            .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
    }
}

extension View {
    func gtPanel(_ fill: Color = GTTheme.paper) -> some View {
        modifier(GTPanelModifier(fill: fill))
    }
}

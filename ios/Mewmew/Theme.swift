import SwiftUI
import UIKit

enum Theme {
    static let background = Color(lightHex: "#FFFFFF", darkHex: "#111113")
    static let surface = Color(lightHex: "#F6F6F7", darkHex: "#1B1B1F")
    static let surfaceDeep = Color(lightHex: "#ECECEE", darkHex: "#26262C")
    static let accent = Color(hex: "#F97316")
    static let primaryText = Color(lightHex: "#18181B", darkHex: "#F4F4F5")
    static let secondaryText = Color(hex: "#71717A")
    static let border = Color(lightHex: "#E4E4E7", darkHex: "#2A2A30")
    static let overdue = Color(hex: "#DC2626")
    static let completed = Color(hex: "#16A34A")

    static let cornerRadius: CGFloat = 12
    static let stageCornerRadius: CGFloat = 26
    static let borderWidth: CGFloat = 1
}

private extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(lightHex: String, darkHex: String) {
        self.init(
            uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
            }
        )
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

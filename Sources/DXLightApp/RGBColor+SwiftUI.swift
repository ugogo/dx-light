import AppKit
import DXLightCore
import SwiftUI

extension DXLightCore.RGBColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }
}

extension Color {
    func rgbColor() -> DXLightCore.RGBColor? {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return DXLightCore.RGBColor(
            red: UInt8(min(255, max(0, Int((nsColor.redComponent * 255).rounded())))),
            green: UInt8(min(255, max(0, Int((nsColor.greenComponent * 255).rounded())))),
            blue: UInt8(min(255, max(0, Int((nsColor.blueComponent * 255).rounded()))))
        )
    }
}

import AppKit
import UsageCore

/// Palette mirroring the Windows app (MainWindow.xaml / TrayIcon.cs).
enum Theme {
    static let normal = NSColor(srgbRed: 0x2E / 255, green: 0xCC / 255, blue: 0x71 / 255, alpha: 1)
    static let warning = NSColor(srgbRed: 0xF3 / 255, green: 0x9C / 255, blue: 0x12 / 255, alpha: 1)
    static let critical = NSColor(srgbRed: 0xE7 / 255, green: 0x4C / 255, blue: 0x3C / 255, alpha: 1)
    static let stale = NSColor(srgbRed: 0x55 / 255, green: 0x55 / 255, blue: 0x55 / 255, alpha: 1)
    static let amber = warning
    static let gray = NSColor(srgbRed: 0x9A / 255, green: 0x9A / 255, blue: 0xA8 / 255, alpha: 1)

    static let cardBackground = NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x28 / 255, alpha: 0.93)
    static let label = NSColor(srgbRed: 0xDD / 255, green: 0xDD / 255, blue: 0xDD / 255, alpha: 1)
    static let percent = NSColor.white
    static let track = NSColor(white: 0, alpha: 0.2)

    static func barColor(for utilization: Double) -> NSColor {
        switch UsageFormatting.level(for: utilization) {
        case .critical: return critical
        case .warning: return warning
        case .normal: return normal
        }
    }
}

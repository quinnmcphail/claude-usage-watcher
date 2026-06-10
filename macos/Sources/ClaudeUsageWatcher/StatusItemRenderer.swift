import AppKit
import UsageCore

/// Renders the menu-bar badge image and tooltip, mirroring TrayIcon.cs.
enum StatusItemRenderer {
    /// The rounded-rect colored badge with centered white bold percent text.
    /// Drawn at 2x and tagged 18x18pt so it renders crisply on Retina. Not a
    /// template image: we want the fill color to show through.
    static func makeImage(fiveHour: Double?, isStale: Bool, hasCredentials: Bool) -> NSImage {
        let unknown = !hasCredentials || fiveHour == nil
        let fill: NSColor
        if unknown || isStale {
            fill = Theme.stale
        } else {
            fill = Theme.barColor(for: fiveHour!)
        }

        let text = badgeText(fiveHour: fiveHour, unknown: unknown)

        let pt: CGFloat = 18
        let scale: CGFloat = 2
        let px = Int(pt * scale)

        let image = NSImage(size: NSSize(width: pt, height: pt))
        image.addRepresentation(makeRep(pixels: px, pt: pt, fill: fill, text: text))
        image.isTemplate = false
        return image
    }

    private static func makeRep(pixels: Int, pt: CGFloat, fill: NSColor, text: String) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)!
        rep.size = NSSize(width: pt, height: pt)

        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.setAllowsAntialiasing(true)

        // Use point-space coordinates; the bitmap rep handles the 2x scale.
        let inset: CGFloat = 1
        let rect = NSRect(x: inset, y: inset, width: pt - 2 * inset, height: pt - 2 * inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        fill.setFill()
        path.fill()

        let fontSize: CGFloat = text.count >= 3 ? 9 : 12
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: NSColor.white
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let size = attr.size()
        let origin = NSPoint(x: (pt - size.width) / 2, y: (pt - size.height) / 2)
        attr.draw(at: origin)

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func badgeText(fiveHour: Double?, unknown: Bool) -> String {
        guard !unknown, let fiveHour else {
            return "--"
        }
        // Round half away from zero, like the C#.
        let pct = Int((fiveHour).rounded(.toNearestOrAwayFromZero))
        if pct >= 100 { return "99+" }
        if pct < 0 { return "0" }
        return String(pct)
    }

    /// Tooltip text, mirroring TrayIcon.BuildTooltip.
    static func tooltip(snapshot: UsageSnapshot?, hasCredentials: Bool, isStale: Bool, now: Date) -> String {
        if !hasCredentials {
            return "No Claude Code credentials"
        }
        guard let snapshot else {
            return "Claude Usage Watcher (no data)"
        }

        let fivePct = snapshot.fiveHour.map { "\(Int($0.utilization.rounded()))%" } ?? "--"
        let fiveCd = UsageFormatting.formatCountdown(snapshot.fiveHour?.resetsAt, now: now)
        let weekPct = snapshot.sevenDay.map { "\(Int($0.utilization.rounded()))%" } ?? "--"

        var text = fiveCd.isEmpty
            ? "5h: \(fivePct) | wk: \(weekPct)"
            : "5h: \(fivePct) (\(fiveCd)) | wk: \(weekPct)"

        if isStale {
            text += " [stale]"
        }
        return text
    }
}

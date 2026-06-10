import AppKit
import UsageCore

/// One usage metric: title + bold percent, a 10pt rounded progress bar, and a
/// small gray caption. Mirrors a XAML metric block in MainWindow.xaml.
final class MetricRow: NSStackView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "--")
    private let caption = NSTextField(labelWithString: "")
    private let barTrack = BarTrackView()

    init(title: String) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 3
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = Theme.label

        percentLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        percentLabel.textColor = Theme.percent
        percentLabel.alignment = .right

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 0).isActive = true
        let header = NSStackView(views: [titleLabel, spacer, percentLabel])
        header.orientation = .horizontal
        header.translatesAutoresizingMaskIntoConstraints = false
        header.distribution = .fill
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        caption.font = .systemFont(ofSize: 11)
        caption.textColor = Theme.gray
        caption.lineBreakMode = .byTruncatingTail

        addArrangedSubview(header)
        addArrangedSubview(barTrack)
        addArrangedSubview(caption)

        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: widthAnchor),
            barTrack.widthAnchor.constraint(equalTo: widthAnchor),
            barTrack.heightAnchor.constraint(equalToConstant: 10),
            caption.widthAnchor.constraint(equalTo: widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Update from a window (or nil). `captionText` is computed by the panel so the
    /// 5-hour row can append its burn-rate suffix.
    func update(window: UsageWindow?, captionText: String) {
        guard let window else {
            percentLabel.stringValue = "--"
            barTrack.fillColor = Theme.normal
            barTrack.fraction = 0
            caption.stringValue = ""
            return
        }

        let value = min(max(window.utilization, 0), 100)
        percentLabel.stringValue = "\(Int(window.utilization.rounded()))%"
        barTrack.fillColor = Theme.barColor(for: window.utilization)
        barTrack.fraction = CGFloat(value / 100.0)
        caption.stringValue = captionText
    }
}

/// Self-drawing rounded progress bar: dark track, colored fill. Recomputes on
/// every layout so it stays correct as the popover resizes.
private final class BarTrackView: NSView {
    var fraction: CGFloat = 0 { didSet { needsLayout = true } }
    var fillColor: NSColor = Theme.normal { didSet { fillLayer.backgroundColor = fillColor.cgColor } }

    private let fillLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.track.cgColor
        layer?.cornerRadius = 5
        fillLayer.backgroundColor = fillColor.cgColor
        fillLayer.cornerRadius = 5
        layer?.addSublayer(fillLayer)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = CGRect(
            x: 0, y: 0,
            width: max(0, bounds.width * fraction),
            height: bounds.height)
        CATransaction.commit()
    }
}

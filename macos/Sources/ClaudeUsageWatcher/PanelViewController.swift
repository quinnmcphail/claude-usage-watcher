import AppKit
import UsageCore

/// The popover panel: title row + expand toggle, 5-hour and weekly rows, optional
/// per-model rows when expanded, and a status line. Mirrors MainWindow.xaml(.cs).
final class PanelViewController: NSViewController {
    private let settings: () -> Settings
    private let onToggleExpand: () -> Void

    private let titleLabel = NSTextField(labelWithString: "Claude Usage")
    private let expandButton = NSButton()

    private let fiveRow = MetricRow(title: "5-hour window")
    private let weekRow = MetricRow(title: "Weekly")
    private let opusRow = MetricRow(title: "Weekly (Opus)")
    private let sonnetRow = MetricRow(title: "Weekly (Sonnet)")
    private let noPerModel = NSTextField(labelWithString: "no per-model data")
    private let statusLabel = NSTextField(labelWithString: "")

    private let stack = NSStackView()

    init(settings: @escaping () -> Settings, onToggleExpand: @escaping () -> Void) {
        self.settings = settings
        self.onToggleExpand = onToggleExpand
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.cardBackground.cgColor

        // Title row.
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.textColor = Theme.label

        expandButton.title = settings().expanded ? "\u{25BE}" : "\u{25B8}" // ▾ / ▸
        expandButton.bezelStyle = .inline
        expandButton.isBordered = false
        expandButton.contentTintColor = Theme.label
        expandButton.font = .systemFont(ofSize: 13)
        expandButton.target = self
        expandButton.action = #selector(toggleExpand)
        expandButton.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        let titleRow = NSStackView(views: [titleLabel, spacer, expandButton])
        titleRow.orientation = .horizontal
        titleRow.distribution = .fill
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        noPerModel.font = .systemFont(ofSize: 11)
        noPerModel.textColor = Theme.gray

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = Theme.gray
        statusLabel.lineBreakMode = .byTruncatingTail

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.required, for: .vertical)

        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(fiveRow)
        stack.addArrangedSubview(weekRow)
        stack.addArrangedSubview(opusRow)
        stack.addArrangedSubview(sonnetRow)
        stack.addArrangedSubview(noPerModel)
        stack.addArrangedSubview(statusLabel)

        for row in [titleRow, fiveRow, weekRow, opusRow, sonnetRow] {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.widthAnchor.constraint(equalToConstant: 300)
        ])

        view = container
    }

    @objc private func toggleExpand() {
        onToggleExpand()
        expandButton.title = settings().expanded ? "\u{25BE}" : "\u{25B8}"
    }

    /// Renders the cached snapshot. `service` provides staleness, credentials, and
    /// burn-rate projection. `lastOutcome` drives the no-snapshot status text.
    func render(service: UsageService, lastOutcome: FetchOutcome, now: Date = Date()) {
        let snap = service.lastGood

        // 5-hour row, with burn-rate suffix appended like ApplyBurnRateSuffix.
        fiveRow.update(window: snap?.fiveHour, captionText: fiveCaption(snap?.fiveHour, service: service, now: now))
        weekRow.update(window: snap?.sevenDay, captionText: caption(snap?.sevenDay, now: now))
        opusRow.update(window: snap?.sevenDayOpus, captionText: caption(snap?.sevenDayOpus, now: now))
        sonnetRow.update(window: snap?.sevenDaySonnet, captionText: caption(snap?.sevenDaySonnet, now: now))

        let expanded = settings().expanded
        let opusAvailable = snap?.sevenDayOpus != nil
        let sonnetAvailable = snap?.sevenDaySonnet != nil
        opusRow.isHidden = !(expanded && opusAvailable)
        sonnetRow.isHidden = !(expanded && sonnetAvailable)
        noPerModel.isHidden = !(expanded && !opusAvailable && !sonnetAvailable)

        statusLabel.stringValue = buildStatus(service: service, lastOutcome: lastOutcome, snap: snap)
        statusLabel.textColor = (!service.hasCredentials || service.isStale) ? Theme.amber : Theme.gray

        view.window?.layoutIfNeeded()
    }

    private func caption(_ window: UsageWindow?, now: Date) -> String {
        guard window != nil else { return "" }
        let cd = UsageFormatting.formatCountdown(window?.resetsAt, now: now)
        return cd.isEmpty ? "" : "resets in \(cd)"
    }

    /// 5-hour caption with the burn-rate suffix — a faithful port of ApplyBurnRateSuffix.
    private func fiveCaption(_ five: UsageWindow?, service: UsageService, now: Date) -> String {
        guard let five else { return "" }
        var text = caption(five, now: now)

        guard let ttc = service.projectTimeToCap(now: now) else { return text }
        let capInstant = now.addingTimeInterval(ttc)

        // Irrelevant if the window resets before the projected cap.
        if let resetsAt = five.resetsAt, capInstant >= resetsAt {
            return text
        }

        let capCd = UsageFormatting.formatCountdown(capInstant, now: now)
        if capCd.isEmpty { return text }

        text = text.isEmpty ? "\u{2248}caps in \(capCd)" : "\(text) \u{00B7} \u{2248}caps in \(capCd)"
        return text
    }

    private func buildStatus(service: UsageService, lastOutcome: FetchOutcome, snap: UsageSnapshot?) -> String {
        if !service.hasCredentials {
            return "\u{26A0} no Claude Code credentials found"
        }

        guard let snap else {
            switch lastOutcome {
            case .rateLimited: return "\u{26A0} rate limited \u{2014} retrying"
            case .authFailed: return "\u{26A0} token expired \u{2014} retrying"
            case .error: return "\u{26A0} no data yet"
            default: return "updating\u{2026}"
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let clock = formatter.string(from: snap.fetchedAt)
        return service.isStale
            ? "\u{26A0} stale \u{2014} last updated \(clock)"
            : "updated \(clock)"
    }
}

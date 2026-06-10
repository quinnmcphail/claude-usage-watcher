using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using ClaudeUsageWatcher.Core;

namespace ClaudeUsageWatcher;

public partial class MainWindow : Window
{
    private static readonly SolidColorBrush NormalBrush =
        new(Color.FromRgb(0x2E, 0xCC, 0x71));
    private static readonly SolidColorBrush WarningBrush =
        new(Color.FromRgb(0xF3, 0x9C, 0x12));
    private static readonly SolidColorBrush CriticalBrush =
        new(Color.FromRgb(0xE7, 0x4C, 0x3C));
    private static readonly SolidColorBrush AmberBrush =
        new(Color.FromRgb(0xF3, 0x9C, 0x12));
    private static readonly SolidColorBrush GrayBrush =
        new(Color.FromRgb(0x9A, 0x9A, 0xA8));

    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(120);

    private readonly UsageService _service;
    private readonly Settings _settings;
    private readonly DispatcherTimer _pollTimer;
    private readonly DispatcherTimer _tickTimer;
    private readonly SemaphoreSlim _pollGate = new(1, 1);

    private TrayIcon? _trayIcon;
    private bool _exiting;
    private FetchOutcome _lastOutcome = FetchOutcome.Success;

    static MainWindow()
    {
        NormalBrush.Freeze();
        WarningBrush.Freeze();
        CriticalBrush.Freeze();
        AmberBrush.Freeze();
        GrayBrush.Freeze();
    }

    public MainWindow()
    {
        InitializeComponent();
        _settings = Settings.Load();
        _service = new UsageService(_settings.NotifyWarnAt, _settings.NotifyCriticalAt);

        _pollTimer = new DispatcherTimer { Interval = PollInterval };
        _pollTimer.Tick += async (_, _) => await DoPollAsync();

        _tickTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _tickTimer.Tick += (_, _) => RenderFromCache();
    }

    public void InitializeAndShow()
    {
        _trayIcon = new TrayIcon(_settings.NotificationsEnabled);
        _trayIcon.LeftClicked += ToggleVisibility;
        _trayIcon.RefreshRequested += () => _ = DoPollAsync();
        _trayIcon.ExitRequested += ExitApplication;
        _trayIcon.NotificationsToggled += OnNotificationsToggled;

        UpdateExpandButton();

        ApplyInitialPosition();

        if (!_settings.Hidden)
        {
            Show();
        }

        _pollTimer.Start();
        _tickTimer.Start();

        _ = DoPollAsync();
    }

    private void ApplyInitialPosition()
    {
        if (_settings.Left is double l && _settings.Top is double t)
        {
            Left = l;
            Top = t;
            return;
        }

        // Bottom-right of the primary working area with 16px margin.
        var work = SystemParameters.WorkArea;
        const double margin = 16;
        // Width is fixed (300); height not yet measured, estimate then re-place after load.
        Left = work.Right - Width - margin;
        Top = work.Bottom - 200 - margin;

        Loaded += (_, _) =>
        {
            if (_settings.Left is null || _settings.Top is null)
            {
                Left = work.Right - ActualWidth - margin;
                Top = work.Bottom - ActualHeight - margin;
            }
        };
    }

    private async Task DoPollAsync()
    {
        if (!await _pollGate.WaitAsync(0))
        {
            return;
        }

        try
        {
            FetchResult result = await _service.PollAsync();
            _lastOutcome = result.Outcome;
            RenderFromCache();

            if (result.Notification is ThresholdEvent ev && _settings.NotificationsEnabled)
            {
                ShowNotification(ev, result.Snapshot);
            }
        }
        finally
        {
            _pollGate.Release();
        }
    }

    private void ShowNotification(ThresholdEvent ev, UsageSnapshot? snap)
    {
        UsageWindow? five = snap?.FiveHour;
        if (_trayIcon is null || five is null)
        {
            return;
        }

        int pct = (int)Math.Round(five.Utilization);
        var now = DateTimeOffset.Now;

        switch (ev)
        {
            case ThresholdEvent.Reset:
                _trayIcon.ShowNotification(
                    "Claude usage",
                    $"5-hour window reset — usage at {pct}%",
                    warning: false);
                break;
            case ThresholdEvent.Warning:
            case ThresholdEvent.Critical:
                string cd = UsageFormatting.FormatCountdown(five.ResetsAt, now);
                string text = string.IsNullOrEmpty(cd)
                    ? $"5-hour window at {pct}%"
                    : $"5-hour window at {pct}% — resets in {cd}";
                _trayIcon.ShowNotification(
                    "Claude usage",
                    text,
                    warning: ev == ThresholdEvent.Critical);
                break;
        }
    }

    private void RenderFromCache()
    {
        var now = DateTimeOffset.Now;
        UsageSnapshot? snap = _service.LastGood;

        UpdateMetric(FiveBar, FivePercent, FiveReset, snap?.FiveHour, now);
        ApplyBurnRateSuffix(snap?.FiveHour, now);
        UpdateMetric(WeekBar, WeekPercent, WeekReset, snap?.SevenDay, now);
        UpdateMetric(OpusBar, OpusPercent, OpusReset, snap?.SevenDayOpus, now);
        UpdateMetric(SonnetBar, SonnetPercent, SonnetReset, snap?.SevenDaySonnet, now);

        UpdatePerModelVisibility(snap);

        StatusText.Text = BuildStatus(snap);
        StatusText.Foreground =
            (!_service.HasCredentials || _service.IsStale) ? AmberBrush : GrayBrush;

        _trayIcon?.Update(snap, _service.IsStale, _service.HasCredentials);
    }

    private static void UpdateMetric(
        System.Windows.Controls.ProgressBar bar,
        System.Windows.Controls.TextBlock percent,
        System.Windows.Controls.TextBlock reset,
        UsageWindow? window,
        DateTimeOffset now)
    {
        if (window is null)
        {
            bar.Value = 0;
            bar.Foreground = NormalBrush;
            percent.Text = "--";
            reset.Text = "";
            return;
        }

        double value = Math.Clamp(window.Utilization, 0, 100);
        bar.Value = value;
        bar.Foreground = UsageFormatting.GetLevel(window.Utilization) switch
        {
            UsageLevel.Critical => CriticalBrush,
            UsageLevel.Warning => WarningBrush,
            _ => NormalBrush
        };
        percent.Text = $"{(int)Math.Round(window.Utilization)}%";

        string cd = UsageFormatting.FormatCountdown(window.ResetsAt, now);
        reset.Text = string.IsNullOrEmpty(cd) ? "" : $"resets in {cd}";
    }

    private void ApplyBurnRateSuffix(UsageWindow? five, DateTimeOffset now)
    {
        if (five is null)
        {
            return;
        }

        TimeSpan? projection = _service.ProjectTimeToCap(now);
        if (projection is not TimeSpan ttc)
        {
            return;
        }

        DateTimeOffset capInstant = now + ttc;

        // Irrelevant if the window resets before the projected cap.
        if (five.ResetsAt is DateTimeOffset resetsAt && capInstant >= resetsAt)
        {
            return;
        }

        string capCd = UsageFormatting.FormatCountdown(capInstant, now);
        if (string.IsNullOrEmpty(capCd))
        {
            return;
        }

        FiveReset.Text = string.IsNullOrEmpty(FiveReset.Text)
            ? $"≈caps in {capCd}"
            : $"{FiveReset.Text} · ≈caps in {capCd}";
    }

    private void UpdatePerModelVisibility(UsageSnapshot? snap)
    {
        bool expanded = _settings.Expanded;
        bool opusAvailable = snap?.SevenDayOpus is not null;
        bool sonnetAvailable = snap?.SevenDaySonnet is not null;

        OpusSection.Visibility = (expanded && opusAvailable)
            ? Visibility.Visible
            : Visibility.Collapsed;
        SonnetSection.Visibility = (expanded && sonnetAvailable)
            ? Visibility.Visible
            : Visibility.Collapsed;

        NoPerModelText.Visibility = (expanded && !opusAvailable && !sonnetAvailable)
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void OnNotificationsToggled(bool enabled)
    {
        _settings.NotificationsEnabled = enabled;
        _settings.Save();
    }

    private void ExpandButton_Click(object sender, RoutedEventArgs e)
    {
        _settings.Expanded = !_settings.Expanded;
        _settings.Save();
        UpdateExpandButton();
        RenderFromCache();
    }

    private void UpdateExpandButton()
    {
        ExpandButton.Content = _settings.Expanded ? "▾" : "▸";
    }

    private string BuildStatus(UsageSnapshot? snap)
    {
        if (!_service.HasCredentials)
        {
            return "⚠ no Claude Code credentials found";
        }

        if (snap is null)
        {
            return _lastOutcome switch
            {
                FetchOutcome.RateLimited => "⚠ rate limited — retrying",
                FetchOutcome.AuthFailed => "⚠ token expired — retrying",
                FetchOutcome.Error => "⚠ no data yet",
                _ => "updating…"
            };
        }

        string clock = snap.FetchedAt.ToLocalTime().ToString("HH:mm:ss");
        return _service.IsStale
            ? $"⚠ stale — last updated {clock}"
            : $"updated {clock}";
    }

    private void ToggleVisibility()
    {
        if (IsVisible)
        {
            HideToTray();
        }
        else
        {
            ShowFromTray();
        }
    }

    public void ShowFromTray()
    {
        Show();
        _settings.Hidden = false;
        _settings.Save();
        WindowState = WindowState.Normal;
        Topmost = false;
        Topmost = true; // toggle to force the window above other topmost windows
        Activate();
        RenderFromCache();
    }

    private void HideToTray()
    {
        PersistPosition();
        _settings.Hidden = true;
        _settings.Save();
        Hide();
    }

    private void PersistPosition()
    {
        if (!double.IsNaN(Left) && !double.IsNaN(Top))
        {
            _settings.Left = Left;
            _settings.Top = Top;
        }
    }

    private void RootBorder_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
            PersistPosition();
            _settings.Save();
        }
    }

    private void HideButton_Click(object sender, RoutedEventArgs e) => HideToTray();

    private void CloseButton_Click(object sender, RoutedEventArgs e) => HideToTray();

    private void ExitApplication()
    {
        if (_exiting)
        {
            return;
        }

        _exiting = true;

        PersistPosition();
        _settings.Save();

        _pollTimer.Stop();
        _tickTimer.Stop();

        _trayIcon?.Dispose();
        _trayIcon = null;

        _service.Dispose();

        Application.Current.Shutdown();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        // The X/window-close path should hide rather than terminate, unless we are
        // intentionally exiting via the tray menu.
        if (!_exiting)
        {
            e.Cancel = true;
            HideToTray();
            return;
        }

        base.OnClosing(e);
    }
}

using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using ClaudeUsageWatcher.Core;
using WinForms = System.Windows.Forms;

namespace ClaudeUsageWatcher;

public sealed class TrayIcon : IDisposable
{
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    private readonly WinForms.NotifyIcon _notifyIcon;
    private readonly WinForms.ToolStripMenuItem _startWithWindowsItem;

    private Icon? _currentIcon;
    private IntPtr _currentIconHandle = IntPtr.Zero;
    private bool _disposed;

    public event Action? LeftClicked;
    public event Action? RefreshRequested;
    public event Action? ExitRequested;

    public TrayIcon()
    {
        _notifyIcon = new WinForms.NotifyIcon
        {
            Visible = true,
            Text = "Claude Usage Watcher"
        };

        var menu = new WinForms.ContextMenuStrip();

        var refreshItem = new WinForms.ToolStripMenuItem("Refresh now");
        refreshItem.Click += (_, _) => RefreshRequested?.Invoke();

        _startWithWindowsItem = new WinForms.ToolStripMenuItem("Start with Windows")
        {
            CheckOnClick = false,
            Checked = Autostart.IsEnabled()
        };
        _startWithWindowsItem.Click += OnToggleAutostart;

        var exitItem = new WinForms.ToolStripMenuItem("Exit");
        exitItem.Click += (_, _) => ExitRequested?.Invoke();

        menu.Items.Add(refreshItem);
        menu.Items.Add(_startWithWindowsItem);
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add(exitItem);

        _notifyIcon.ContextMenuStrip = menu;
        _notifyIcon.MouseClick += OnMouseClick;

        // Initial placeholder icon.
        Update(null, isStale: false, hasCredentials: true);
    }

    private void OnMouseClick(object? sender, WinForms.MouseEventArgs e)
    {
        if (e.Button == WinForms.MouseButtons.Left)
        {
            LeftClicked?.Invoke();
        }
    }

    private void OnToggleAutostart(object? sender, EventArgs e)
    {
        bool ok;
        if (_startWithWindowsItem.Checked)
        {
            ok = Autostart.Disable();
            if (ok)
            {
                _startWithWindowsItem.Checked = false;
            }
        }
        else
        {
            ok = Autostart.Enable();
            if (ok)
            {
                _startWithWindowsItem.Checked = true;
            }
        }
    }

    public void Update(UsageSnapshot? snapshot, bool isStale, bool hasCredentials)
    {
        if (_disposed)
        {
            return;
        }

        double? fiveHour = snapshot?.FiveHour?.Utilization;
        bool unknown = !hasCredentials || snapshot is null || fiveHour is null;

        UsageLevel level = unknown
            ? UsageLevel.Normal
            : UsageFormatting.GetLevel(fiveHour!.Value);

        Color fill = (unknown || isStale)
            ? Color.FromArgb(0x55, 0x55, 0x55)
            : level switch
            {
                UsageLevel.Critical => Color.FromArgb(0xE7, 0x4C, 0x3C),
                UsageLevel.Warning => Color.FromArgb(0xF3, 0x9C, 0x12),
                _ => Color.FromArgb(0x2E, 0xCC, 0x71)
            };

        string text = BuildIconText(fiveHour, unknown);

        SetIcon(RenderIcon(fill, text));
        _notifyIcon.Text = BuildTooltip(snapshot, hasCredentials, isStale);
    }

    private static string BuildIconText(double? fiveHour, bool unknown)
    {
        if (unknown || fiveHour is null)
        {
            return "--";
        }

        int pct = (int)Math.Round(fiveHour.Value, MidpointRounding.AwayFromZero);
        if (pct >= 100)
        {
            return "99+";
        }

        if (pct < 0)
        {
            return "0";
        }

        return pct.ToString();
    }

    private static string BuildTooltip(UsageSnapshot? snapshot, bool hasCredentials, bool isStale)
    {
        if (!hasCredentials)
        {
            return "No Claude Code credentials";
        }

        if (snapshot is null)
        {
            return "Claude Usage Watcher (no data)";
        }

        var now = DateTimeOffset.Now;
        string fivePct = snapshot.FiveHour is null
            ? "--"
            : ((int)Math.Round(snapshot.FiveHour.Utilization)).ToString() + "%";
        string fiveCd = UsageFormatting.FormatCountdown(snapshot.FiveHour?.ResetsAt, now);
        string weekPct = snapshot.SevenDay is null
            ? "--"
            : ((int)Math.Round(snapshot.SevenDay.Utilization)).ToString() + "%";

        string text = string.IsNullOrEmpty(fiveCd)
            ? $"5h: {fivePct} | wk: {weekPct}"
            : $"5h: {fivePct} ({fiveCd}) | wk: {weekPct}";

        if (isStale)
        {
            text += " [stale]";
        }

        if (text.Length > 63)
        {
            text = text.Substring(0, 63);
        }

        return text;
    }

    private static Bitmap RenderIcon(Color fill, string text)
    {
        const int size = 32;
        var bmp = new Bitmap(size, size);

        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAlias;
        g.Clear(Color.Transparent);

        const int margin = 1;
        var rect = new Rectangle(margin, margin, size - 2 * margin - 1, size - 2 * margin - 1);
        using (var path = RoundedRect(rect, 7))
        using (var brush = new SolidBrush(fill))
        {
            g.FillPath(brush, path);
        }

        float fontSize = text.Length >= 3 ? 10f : 13f;
        using var font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Point);
        using var textBrush = new SolidBrush(Color.White);
        using var format = new StringFormat
        {
            Alignment = StringAlignment.Center,
            LineAlignment = StringAlignment.Center
        };
        g.DrawString(text, font, textBrush, new RectangleF(0, 0, size, size), format);

        return bmp;
    }

    private static GraphicsPath RoundedRect(Rectangle bounds, int radius)
    {
        int diameter = radius * 2;
        var path = new GraphicsPath();
        var arc = new Rectangle(bounds.Location, new Size(diameter, diameter));

        path.AddArc(arc, 180, 90);
        arc.X = bounds.Right - diameter;
        path.AddArc(arc, 270, 90);
        arc.Y = bounds.Bottom - diameter;
        path.AddArc(arc, 0, 90);
        arc.X = bounds.Left;
        path.AddArc(arc, 90, 90);
        path.CloseFigure();
        return path;
    }

    private void SetIcon(Bitmap bmp)
    {
        IntPtr newHandle = IntPtr.Zero;
        try
        {
            newHandle = bmp.GetHicon();
            var newIcon = Icon.FromHandle(newHandle);

            Icon? oldIcon = _currentIcon;
            IntPtr oldHandle = _currentIconHandle;

            _notifyIcon.Icon = newIcon;
            _currentIcon = newIcon;
            _currentIconHandle = newHandle;
            newHandle = IntPtr.Zero;

            // Release the previously installed icon's GDI resources.
            oldIcon?.Dispose();
            if (oldHandle != IntPtr.Zero)
            {
                DestroyIcon(oldHandle);
            }
        }
        finally
        {
            // If anything threw after GetHicon but before installation, free the orphan handle.
            if (newHandle != IntPtr.Zero)
            {
                DestroyIcon(newHandle);
            }

            bmp.Dispose();
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        _notifyIcon.Visible = false;
        _notifyIcon.Icon = null;
        _notifyIcon.Dispose();

        _currentIcon?.Dispose();
        if (_currentIconHandle != IntPtr.Zero)
        {
            DestroyIcon(_currentIconHandle);
            _currentIconHandle = IntPtr.Zero;
        }
    }
}

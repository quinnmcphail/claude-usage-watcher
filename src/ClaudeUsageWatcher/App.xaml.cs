using System.Threading;
using System.Windows;

namespace ClaudeUsageWatcher;

public partial class App : System.Windows.Application
{
    private const string MutexName = "ClaudeUsageWatcher_SingleInstance";
    private const string ShowSignalName = "ClaudeUsageWatcher_ShowSignal";

    private MainWindow? _mainWindow;
    private Mutex? _instanceMutex;
    private EventWaitHandle? _showSignal;
    private Thread? _signalThread;
    private volatile bool _shuttingDown;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _instanceMutex = new Mutex(initiallyOwned: true, MutexName, out bool createdNew);

        if (!createdNew)
        {
            // Another instance is already running: ask it to surface its window, then exit.
            try
            {
                using var existing = EventWaitHandle.OpenExisting(ShowSignalName);
                existing.Set();
            }
            catch (WaitHandleCannotBeOpenedException)
            {
                // The primary instance hasn't created the handle yet; nothing to signal.
            }

            _instanceMutex.Dispose();
            _instanceMutex = null;
            Shutdown();
            return;
        }

        _showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, ShowSignalName);

        _signalThread = new Thread(SignalLoop)
        {
            IsBackground = true,
            Name = "ShowSignalListener"
        };
        _signalThread.Start();

        _mainWindow = new MainWindow();
        MainWindow = _mainWindow;
        _mainWindow.InitializeAndShow();
    }

    private void SignalLoop()
    {
        EventWaitHandle? signal = _showSignal;
        if (signal is null)
        {
            return;
        }

        while (!_shuttingDown)
        {
            try
            {
                if (!signal.WaitOne(500))
                {
                    continue;
                }
            }
            catch (ObjectDisposedException)
            {
                return;
            }

            if (_shuttingDown)
            {
                return;
            }

            Dispatcher.Invoke(() => _mainWindow?.ShowFromTray());
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _shuttingDown = true;

        _showSignal?.Set(); // wake the listener so it observes the shutdown flag and ends
        _signalThread?.Join(1000);

        _showSignal?.Dispose();
        _showSignal = null;

        _instanceMutex?.Dispose();
        _instanceMutex = null;

        base.OnExit(e);
    }
}

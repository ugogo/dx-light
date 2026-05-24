using DXLight.Core;
using Microsoft.Win32;
using System.ComponentModel;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace DXLight.Tray;

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly LightController _controller = new();
    private readonly NotifyIcon _notifyIcon;
    private readonly ToolStripMenuItem _togglePowerItem;
    private readonly ToolStripMenuItem _refreshItem;
    private readonly SynchronizationContext? _uiContext;
    private ControlForm? _controlForm;
    private Icon? _currentIcon;

    public TrayApplicationContext()
    {
        _uiContext = SynchronizationContext.Current;
        _togglePowerItem = new ToolStripMenuItem("Toggle power", null, async (_, _) => await _controller.TogglePowerAsync());
        _refreshItem = new ToolStripMenuItem("Refresh", null, async (_, _) => await _controller.RefreshConnectionAsync());
        var quitItem = new ToolStripMenuItem("Quit", null, (_, _) => ExitThread());

        _notifyIcon = new NotifyIcon
        {
            Text = "DX Light",
            ContextMenuStrip = new ContextMenuStrip(),
            Visible = true
        };
        _notifyIcon.ContextMenuStrip.Items.AddRange([_togglePowerItem, _refreshItem, new ToolStripSeparator(), quitItem]);
        _notifyIcon.MouseClick += NotifyIconOnMouseClick;
        _notifyIcon.MouseDoubleClick += async (_, args) =>
        {
            if (args.Button == MouseButtons.Left)
            {
                await _controller.TogglePowerAsync();
            }
        };

        _controller.PropertyChanged += ControllerOnPropertyChanged;
        SystemEvents.PowerModeChanged += SystemEventsOnPowerModeChanged;
        _controller.Start();
        UpdateTrayState();
    }

    protected override void ExitThreadCore()
    {
        SystemEvents.PowerModeChanged -= SystemEventsOnPowerModeChanged;
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _currentIcon?.Dispose();
        _controlForm?.Close();
        _controller.Dispose();
        base.ExitThreadCore();
    }

    private void NotifyIconOnMouseClick(object? sender, MouseEventArgs args)
    {
        if (args.Button == MouseButtons.Left)
        {
            ShowControlForm();
        }
    }

    private void ShowControlForm()
    {
        if (_controlForm is null || _controlForm.IsDisposed)
        {
            _controlForm = new ControlForm(_controller);
            _controlForm.FormClosed += (_, _) => _controlForm = null;
        }

        _controlForm.Show();
        _controlForm.WindowState = FormWindowState.Normal;
        _controlForm.Activate();
    }

    private void ControllerOnPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_uiContext is not null && SynchronizationContext.Current != _uiContext)
        {
            _uiContext.Post(_ => UpdateTrayState(), null);
            return;
        }

        UpdateTrayState();
    }

    private void SystemEventsOnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        switch (e.Mode)
        {
            case PowerModes.Suspend:
                _controller.PrepareForSystemSleepAsync().GetAwaiter().GetResult();
                PostUpdateTrayState();
                break;
            case PowerModes.Resume:
                _controller.RestoreAfterSystemWakeAsync().GetAwaiter().GetResult();
                PostUpdateTrayState();
                break;
        }
    }

    private void PostUpdateTrayState()
    {
        if (_uiContext is not null && SynchronizationContext.Current != _uiContext)
        {
            _uiContext.Post(_ => UpdateTrayState(), null);
            return;
        }

        UpdateTrayState();
    }

    private void UpdateTrayState()
    {
        var oldIcon = _currentIcon;
        _currentIcon = CreateStatusIcon();
        _notifyIcon.Icon = _currentIcon;
        _notifyIcon.Text = TooltipText();
        _togglePowerItem.Enabled = _controller.Status.State == ConnectionState.Connected && !_controller.IsBusy;
        _refreshItem.Enabled = !_controller.IsBusy;
        oldIcon?.Dispose();
    }

    private string TooltipText()
    {
        return _controller.Status.State switch
        {
            ConnectionState.Connected => _controller.IsOn ? "DX Light - on" : "DX Light - off",
            ConnectionState.Searching => "DX Light - searching",
            ConnectionState.Error => "DX Light - not connected",
            _ => "DX Light"
        };
    }

    private Icon CreateStatusIcon()
    {
        var color = _controller.Status.State switch
        {
            ConnectionState.Connected when _controller.IsOn => Color.Gold,
            ConnectionState.Connected => Color.DimGray,
            ConnectionState.Searching => Color.DarkOrange,
            ConnectionState.Error => Color.Firebrick,
            _ => Color.DimGray
        };

        using var bitmap = new Bitmap(32, 32);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.Clear(Color.Transparent);
            using var brush = new SolidBrush(color);
            using var pen = new Pen(Color.FromArgb(220, Color.Black), 2);
            graphics.FillEllipse(brush, 8, 4, 16, 16);
            graphics.DrawEllipse(pen, 8, 4, 16, 16);
            using var baseBrush = new SolidBrush(Color.FromArgb(230, 60, 60, 60));
            graphics.FillRoundedRectangle(baseBrush, new Rectangle(11, 20, 10, 7), 2);
        }

        var handle = bitmap.GetHicon();
        try
        {
            return (Icon)Icon.FromHandle(handle).Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);
}

internal static class GraphicsExtensions
{
    public static void FillRoundedRectangle(this Graphics graphics, Brush brush, Rectangle bounds, int radius)
    {
        using var path = new GraphicsPath();
        var diameter = radius * 2;
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        graphics.FillPath(brush, path);
    }
}

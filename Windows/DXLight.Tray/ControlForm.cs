using DXLight.Core;
using System.ComponentModel;

namespace DXLight.Tray;

internal sealed class ControlForm : Form
{
    private readonly LightController _controller;
    private readonly Label _statusLabel = new();
    private readonly CheckBox _powerCheckBox = new();
    private readonly TrackBar _brightnessTrackBar = new();
    private readonly Label _brightnessValueLabel = new();
    private readonly FlowLayoutPanel _presetPanel = new();
    private readonly Button _customColorButton = new();
    private readonly CheckBox _startupCheckBox = new();
    private readonly CheckBox _smoothCheckBox = new();
    private readonly CheckBox _turnOnUsbCheckBox = new();
    private bool _updatingUi;
    private bool _brightnessDragging;

    public ControlForm(LightController controller)
    {
        _controller = controller;
        Text = "DX Light";
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(360, 460);

        BuildUi();
        _controller.PropertyChanged += ControllerOnPropertyChanged;
        UpdateUi();
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _controller.PropertyChanged -= ControllerOnPropertyChanged;
        base.OnFormClosed(e);
    }

    private void BuildUi()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(14),
            ColumnCount = 1,
            RowCount = 13
        };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.RowStyles.Clear();
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 30));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 30));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));

        var title = new Label
        {
            Text = "DX Light",
            AutoSize = false,
            Dock = DockStyle.Fill,
            Font = new Font(Font.FontFamily, 14, FontStyle.Bold),
            Margin = new Padding(0, 0, 0, 2)
        };
        _statusLabel.AutoSize = false;
        _statusLabel.Dock = DockStyle.Fill;
        _statusLabel.AutoEllipsis = true;
        _statusLabel.ForeColor = SystemColors.GrayText;
        _statusLabel.Margin = new Padding(0, 0, 0, 8);

        _powerCheckBox.Text = "Light is on";
        _powerCheckBox.AutoSize = false;
        _powerCheckBox.Dock = DockStyle.Fill;
        _powerCheckBox.Margin = new Padding(0, 0, 0, 8);
        _powerCheckBox.CheckedChanged += async (_, _) =>
        {
            if (!_updatingUi)
            {
                await _controller.SetPowerAsync(_powerCheckBox.Checked);
            }
        };

        var brightnessLabel = new Label
        {
            Text = "Brightness",
            AutoSize = false,
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.BottomLeft
        };
        _brightnessTrackBar.Minimum = 0;
        _brightnessTrackBar.Maximum = 100;
        _brightnessTrackBar.TickFrequency = 10;
        _brightnessTrackBar.Dock = DockStyle.Fill;
        _brightnessTrackBar.Margin = new Padding(0);
        _brightnessTrackBar.MouseDown += (_, _) => _brightnessDragging = true;
        _brightnessTrackBar.MouseUp += (_, _) => _brightnessDragging = false;
        _brightnessTrackBar.ValueChanged += (_, _) =>
        {
            if (_updatingUi)
            {
                return;
            }

            _brightnessValueLabel.Text = $"{_brightnessTrackBar.Value}%";
            _controller.SetBrightness(_brightnessTrackBar.Value / 100.0);
        };
        _brightnessValueLabel.AutoSize = false;
        _brightnessValueLabel.Dock = DockStyle.Fill;
        _brightnessValueLabel.ForeColor = SystemColors.GrayText;
        _brightnessValueLabel.Margin = new Padding(0, 0, 0, 8);

        var colorLabel = new Label
        {
            Text = "Color",
            AutoSize = false,
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.BottomLeft,
            Margin = new Padding(0)
        };
        _presetPanel.AutoSize = false;
        _presetPanel.Dock = DockStyle.Fill;
        _presetPanel.WrapContents = true;
        _presetPanel.Margin = new Padding(0);

        _customColorButton.Text = "Choose color";
        _customColorButton.AutoSize = false;
        _customColorButton.Width = 112;
        _customColorButton.Height = 30;
        _customColorButton.Margin = new Padding(0, 0, 8, 0);
        _customColorButton.Click += (_, _) => ChooseColor();

        var saveButton = new Button
        {
            Text = "Save preset",
            AutoSize = false,
            Width = 104,
            Height = 30,
            Margin = new Padding(0)
        };
        saveButton.Click += (_, _) => _controller.SaveColorAsPreset();

        var colorButtons = new FlowLayoutPanel
        {
            AutoSize = false,
            Dock = DockStyle.Fill,
            Margin = new Padding(0),
            FlowDirection = FlowDirection.LeftToRight
        };
        colorButtons.Controls.Add(_customColorButton);
        colorButtons.Controls.Add(saveButton);

        _startupCheckBox.Text = "Open at login";
        _startupCheckBox.AutoSize = false;
        _startupCheckBox.Dock = DockStyle.Fill;
        _startupCheckBox.CheckedChanged += (_, _) =>
        {
            if (!_updatingUi)
            {
                StartupManager.SetEnabled(_startupCheckBox.Checked);
            }
        };

        _smoothCheckBox.Text = "Smooth transitions";
        _smoothCheckBox.AutoSize = false;
        _smoothCheckBox.Dock = DockStyle.Fill;
        _smoothCheckBox.CheckedChanged += (_, _) =>
        {
            if (!_updatingUi)
            {
                _controller.SetSmoothTransitions(_smoothCheckBox.Checked);
            }
        };

        _turnOnUsbCheckBox.Text = "Turn on when USB connects";
        _turnOnUsbCheckBox.AutoSize = false;
        _turnOnUsbCheckBox.Dock = DockStyle.Fill;
        _turnOnUsbCheckBox.Margin = new Padding(0, 0, 0, 8);
        _turnOnUsbCheckBox.CheckedChanged += (_, _) =>
        {
            if (!_updatingUi)
            {
                _controller.SetTurnOnWhenUsbConnects(_turnOnUsbCheckBox.Checked);
            }
        };

        var actions = new FlowLayoutPanel
        {
            AutoSize = false,
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            Margin = new Padding(0)
        };
        var refreshButton = new Button { Text = "Refresh", Width = 88, Height = 30 };
        refreshButton.Click += async (_, _) => await _controller.RefreshConnectionAsync();
        var quitButton = new Button { Text = "Quit", Width = 72, Height = 30 };
        quitButton.Click += (_, _) => Application.Exit();
        actions.Controls.Add(refreshButton);
        actions.Controls.Add(quitButton);

        root.Controls.Add(title);
        root.Controls.Add(_statusLabel);
        root.Controls.Add(_powerCheckBox);
        root.Controls.Add(brightnessLabel);
        root.Controls.Add(_brightnessTrackBar);
        root.Controls.Add(_brightnessValueLabel);
        root.Controls.Add(colorLabel);
        root.Controls.Add(_presetPanel);
        root.Controls.Add(colorButtons);
        root.Controls.Add(_startupCheckBox);
        root.Controls.Add(_smoothCheckBox);
        root.Controls.Add(_turnOnUsbCheckBox);
        root.Controls.Add(actions);
        Controls.Add(root);
    }

    private void UpdateUi()
    {
        _updatingUi = true;
        try
        {
            var connected = _controller.Status.State == ConnectionState.Connected;
            _statusLabel.Text = StatusText();
            _powerCheckBox.Enabled = connected;
            _powerCheckBox.Checked = _controller.IsOn;
            _powerCheckBox.Text = _controller.IsOn ? "Light is on" : "Light is off";

            _brightnessTrackBar.Enabled = connected && _controller.IsOn;
            var brightnessValue = Math.Min(Math.Max((int)Math.Round(_controller.Brightness * 100), 0), 100);
            if (!_brightnessDragging && _brightnessTrackBar.Value != brightnessValue)
            {
                _brightnessTrackBar.Value = brightnessValue;
            }
            _brightnessValueLabel.Text = $"{_brightnessTrackBar.Value}%";
            _presetPanel.Enabled = connected && _controller.IsOn;
            _customColorButton.Enabled = connected && _controller.IsOn;
            _startupCheckBox.Checked = StartupManager.IsEnabled();
            _smoothCheckBox.Checked = _controller.SmoothTransitions;
            _turnOnUsbCheckBox.Checked = _controller.TurnOnWhenUsbConnects;
            SyncPresetButtons();
        }
        finally
        {
            _updatingUi = false;
        }
    }

    private string StatusText()
    {
        return _controller.Status.State switch
        {
            ConnectionState.Searching => "Searching for strip...",
            ConnectionState.Connected => $"Connected - {_controller.Status.Device?.Kind.ToString().ToLowerInvariant()}",
            ConnectionState.Error => _controller.Status.Message ?? "Not connected",
            _ => string.Empty
        };
    }

    private void SyncPresetButtons()
    {
        if (_presetPanel.Controls.Count != _controller.ColorPresets.Count)
        {
            BuildPresetButtons();
            return;
        }

        foreach (Button button in _presetPanel.Controls)
        {
            if (button.Tag is ColorPreset preset)
            {
                button.FlatAppearance.BorderSize = preset.Color == _controller.Color ? 2 : 1;
            }
        }
    }

    private void BuildPresetButtons()
    {
        _presetPanel.SuspendLayout();
        _presetPanel.Controls.Clear();
        foreach (var preset in _controller.ColorPresets)
        {
            var button = new Button
            {
                Width = 34,
                Height = 30,
                BackColor = ToDrawingColor(preset.Color),
                FlatStyle = FlatStyle.Flat,
                Margin = new Padding(0, 0, 8, 8),
                Text = preset.Name == ColorPreset.SavedName ? "*" : string.Empty,
                ForeColor = Color.White,
                Tag = preset
            };
            button.FlatAppearance.BorderSize = preset.Color == _controller.Color ? 2 : 1;
            button.Click += (_, _) =>
            {
                if (button.Tag is ColorPreset selected)
                {
                    _controller.SetColor(selected.Color);
                }
            };
            _presetPanel.Controls.Add(button);
        }
        _presetPanel.ResumeLayout();
    }

    private void ChooseColor()
    {
        using var dialog = new ColorDialog
        {
            Color = ToDrawingColor(_controller.Color),
            FullOpen = true
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            _controller.SetColor(new RgbColor(dialog.Color.R, dialog.Color.G, dialog.Color.B));
        }
    }

    private void ControllerOnPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (IsDisposed)
        {
            return;
        }

        if (InvokeRequired)
        {
            BeginInvoke(UpdateUi);
        }
        else
        {
            UpdateUi();
        }
    }

    private static Color ToDrawingColor(RgbColor color) => Color.FromArgb(color.Red, color.Green, color.Blue);
}

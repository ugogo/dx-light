# homebridge-dx-light

Homebridge accessory plugin for controlling a Robobloq DX Light from Apple Home.

The plugin exposes one HomeKit `Lightbulb` accessory with:

- Power
- Brightness

It calls the local DX Light CLI, so the computer running Homebridge remains the USB host for the light.

## Setup

Build the CLI.

macOS:

```bash
cd /Users/ugogo/dev/dx-light
npm run build
```

Windows:

```powershell
cd C:\path\to\dx-light
npm run windows:build
```

Install Homebridge if needed:

```bash
npm install -g homebridge
```

Link this local plugin:

```bash
cd /Users/ugogo/dev/dx-light/Homebridge/homebridge-dx-light
npm link
```

On Windows, run the same `npm link` command from
`C:\path\to\dx-light\Homebridge\homebridge-dx-light`.

Add the accessory to your Homebridge config.

macOS:

```json
{
  "accessory": "DXLight",
  "name": "DX Light",
  "cliPath": "/Users/ugogo/dev/dx-light/.build/release/dx-light-cli",
  "defaultBrightness": 50
}
```

Windows:

```json
{
  "accessory": "DXLight",
  "name": "DX Light",
  "cliPath": "C:\\path\\to\\dx-light\\Windows\\DXLight.Cli\\bin\\Release\\net8.0\\DXLight.Cli.exe",
  "defaultBrightness": 50
}
```

If you omit `cliPath`, the plugin looks for the standard macOS and Windows build outputs in this repository, then falls back to `dx-light-cli` on macOS/Linux or `DXLight.Cli.exe` on Windows.

Then start Homebridge:

```bash
homebridge -D
```

Pair Homebridge in the Apple Home app using the pairing code shown in the Homebridge logs.

## Notes

- Keep the official Robobloq app closed.
- On Windows, avoid running the tray app and Homebridge control at the same time; they can compete for the HID device.
- The plugin serializes CLI calls so Home app taps do not overlap USB writes.
- Color is not exposed yet because the current CLI only supports power and brightness.

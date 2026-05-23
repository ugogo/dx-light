# DX Light

A lightweight native replacement for the official Robobloq DX Light Electron app. Control your monitor LED strip over USB with reliable power, brightness, and color — from a menu bar app on macOS or a system tray app on Windows.

## Features

- Native menu bar (macOS) or notification-area (Windows) UI
- Power, brightness slider, color presets, custom color picker, and saved preset
- Automatic reconnect after sleep or USB replug (1 Hz device poll)
- Optional smooth fades for power, brightness, and color changes
- Open at login
- **Turn on when USB connects** — useful when the strip moves between machines through a KVM
- CLI for listing devices, diagnostics, and hardware smoke tests
- HID transport with serial CDC fallback (vendor `0x1A86`)

## Requirements

| | macOS | Windows |
|---|--------|---------|
| **Run the app** | macOS 13+ | Windows 10/11, [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0) |
| **Build from source** | Xcode Command Line Tools (Swift 5.9+), Node.js (npm scripts) | .NET 8 SDK, Node.js |
| **Hardware** | Robobloq DX Light over USB | Same |

Only one process can control the strip at a time. Quit the official DX Light app (and any other instance of this app) before connecting.

## Quick start

### macOS

```bash
npm run restart    # build dist/DX Light.app and launch
```

Click the light bulb in the menu bar. Option-click toggles power without opening the popover.

### Windows

```powershell
npm run windows:build
npm run windows:start          # launch tray app (no bash)
npm run windows:shortcut       # Desktop shortcut → DX Light.lnk
```

Or double-click **DX Light** on your Desktop after running `windows:shortcut`. Left-click the tray icon for controls. Double-click or use the context menu to toggle power.

## npm scripts

| Script | Description |
|--------|-------------|
| `npm run build` | Release-build menu bar app → `dist/DX Light.app` and CLI → `.build/release/dx-light-cli` |
| `npm run start` | Build, then launch the app if not already running |
| `npm run restart` | Stop, rebuild, and relaunch (use for local dev) |
| `npm run stop` | Quit the running menu bar app |
| `npm run smoke` | Interactive CLI hardware check (macOS, device required) |
| `npm run test` | `swift test` (macOS) |
| `npm run windows:build` | `dotnet build` the Windows solution |
| `npm run windows:start` | Launch the tray app (PowerShell; builds Release if missing) |
| `npm run windows:shortcut` | Create **DX Light.lnk** on the Desktop |
| `npm run windows:test` | `dotnet test` the Windows solution |
| `npm run windows:list` | List connected devices via Windows CLI |

`start` and `restart` always rebuild before launch so you are not testing a stale `dist/DX Light.app`.

## Using the apps

Both apps expose the same controls:

1. **Power** — on/off toggle
2. **Brightness** — 0–100% (only when on)
3. **Color** — built-in presets, custom picker, and a bookmark to save the current color
4. **Open at login** — macOS Login Items; Windows `HKCU\...\Run` (no admin required)
5. **Smooth transitions** — short fades with few USB writes to keep the link responsive
6. **Turn on when USB connects** — after the strip disappears and reconnects (e.g. KVM), the app marks state on and sends the on command. Disable to preserve the previous app power state on reconnect.

**macOS-only:** Option-click the menu bar icon to toggle power without opening the popover. If macOS prompts for login-item approval, enable DX Light under **System Settings → General → Login Items**.

**Windows-only:** Preferences are stored in `%APPDATA%\DXLight\settings.json`. macOS uses standard app `UserDefaults`.

## iPhone / Home app control

DX Light can be exposed to Apple Home through the local Homebridge plugin in
[`Homebridge/homebridge-dx-light`](Homebridge/homebridge-dx-light). The first
version supports power and brightness on macOS and Windows.

Build the CLI, link the plugin, then run Homebridge.

macOS:

```bash
npm run build
npm install -g homebridge
cd Homebridge/homebridge-dx-light
npm link
homebridge -D
```

Windows:

```powershell
npm run windows:build
npm install -g homebridge
cd Homebridge\homebridge-dx-light
npm link
homebridge -D
```

Add this accessory entry to your Homebridge config.

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

Pair Homebridge from the Home app using the setup code printed by Homebridge.
Keep the official Robobloq app closed; Homebridge calls the same CLI that the
hardware smoke test uses. On Windows, do not run the tray app and Homebridge
control at the same time because both can compete for the HID device.

## CLI reference

Core commands work on both platforms:

| Command | Description |
|---------|-------------|
| `list` | Show connected HID/serial devices |
| `info` | Read device ID, version, lamp count |
| `on [0–1.0]` | Turn on (default brightness `0.5`) |
| `off` | Turn off |
| `brightness <0–1.0>` | Set brightness (warm white) |
| `state` | Dump raw state packet and parsed power |
| `test` | Automated off → on → brightness → off sequence |

### macOS

```bash
swift run dx-light-cli list
swift run dx-light-cli on 0.5
swift run dx-light-cli state

# Or use the release binary after npm run build:
.build/release/dx-light-cli test
```

**macOS-only debug commands** (close the menu app first — concurrent HID access causes busy-device errors):

| Command | Description |
|---------|-------------|
| `sniff` | Print unsolicited HID reports (e.g. physical button) |
| `probe` | Poll state and highlight byte changes when you press the strip button |
| `debug-button [log-path]` | Log button-related reports to a file (default `/tmp/dx-light-button-debug.log`) |

The physical bar button is not synced into app state yet; use the debug commands above until the report format is confirmed.

### Windows

```powershell
dotnet run --project Windows\DXLight.Cli -- list
dotnet run --project Windows\DXLight.Cli -- on 0.5
dotnet run --project Windows\DXLight.Cli -- state

# After build:
.\Windows\DXLight.Cli\bin\Debug\net8.0\DXLight.Cli.exe test
```

For a release tray/CLI build:

```powershell
dotnet build Windows/DXLight.Windows.sln -c Release
```

Outputs move to `bin\Release\net8.0-windows\` (tray) and `bin\Release\net8.0\` (CLI).

## Build outputs

| Platform | Menu / tray app | CLI |
|----------|-----------------|-----|
| macOS | `dist/DX Light.app` | `.build/release/dx-light-cli` |
| Windows (Debug) | `Windows\DXLight.Tray\bin\Debug\net8.0-windows\DXLight.Tray.exe` | `Windows\DXLight.Cli\bin\Debug\net8.0\DXLight.Cli.exe` |

## Troubleshooting

**Busy device / control fails**

- Quit the official Robobloq app and any other DX Light instance.
- On macOS, only one process should hold the HID interface.

**CLI works, app does not (macOS)**

- Suspect a stale bundle or a still-running app. Run `npm run restart`.

**Device not found**

Expected USB identifiers:

| Transport | Vendor | Product |
|-----------|--------|---------|
| HID (preferred) | `0x1A86` | `0xFE07` |
| Serial CDC fallback | `0x1A86` | `0xFE0C` |

macOS — check USB visibility:

```bash
system_profiler SPUSBDataType | grep -i -A 8 "1a86\|robobloq"
.build/release/dx-light-cli list
```

Windows — run `npm run windows:list` or the CLI `list` command.

## Hardware smoke test

Run after transport or protocol changes, before a release, or when behavior feels wrong:

```bash
npm run smoke          # macOS — interactive CLI walkthrough
npm run windows:test   # Windows — unit tests (no device required)
```

**Manual app checklist**

1. Quit the official app and this app.
2. Rebuild and launch (`npm run restart` on macOS).
3. Confirm the UI shows **Connected**.
4. Toggle power; change brightness and color.
5. Unplug and replug USB — reconnect within a few seconds.
6. With **Turn on when USB connects** enabled, confirm the strip turns on after reconnect.

If the CLI smoke test passes but the app fails, check for a stale bundle or USB ownership. If both fail, verify discovery and that nothing else holds the HID interface.

## Distribution (macOS)

For personal use, ad-hoc signing is applied by `scripts/build-app.sh`. Re-sign after manual edits:

```bash
codesign --force --deep --sign - "dist/DX Light.app"
```

For wider distribution:

1. Sign with a Developer ID certificate (Xcode or `codesign`).
2. Keep `com.apple.security.device.usb` in [`DXLight.entitlements`](DXLight.entitlements).
3. Notarize with `notarytool` and staple the ticket.

## Architecture

Shared behavior is implemented twice: Swift (`DXLightCore`) for macOS and C# (`Windows/DXLight.Core`) for Windows.

**macOS (Swift)**

- [`Sources/DXLightCore/RobobloqProtocol.swift`](Sources/DXLightCore/RobobloqProtocol.swift) — reverse-engineered `RB` packet format from the official app
- [`Sources/DXLightCore/HIDTransport.swift`](Sources/DXLightCore/HIDTransport.swift) — IOHIDManager output reports
- [`Sources/DXLightCore/SerialTransport.swift`](Sources/DXLightCore/SerialTransport.swift) — 115200 baud CDC fallback
- [`Sources/DXLightCore/LightController.swift`](Sources/DXLightCore/LightController.swift) — connection polling and UI state

**Windows (C#)**

- `Windows/DXLight.Core` — protocol, HID transport, settings store, controller
- `Windows/DXLight.Cli` — command-line diagnostics
- `Windows/DXLight.Tray` — notification-area app

CI runs `swift test` on macOS for every push and pull request to `main` (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

## Out of scope (v1)

- Screen ambilight / audio sync
- BLE / wireless dongle support
- LED effects
- Physical button state sync in the main UI

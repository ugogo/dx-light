# DX Light

A lightweight native macOS menu bar app that controls a Robobloq DX Light monitor LED strip over USB. It replaces the official Electron app for reliable on/off and brightness control.

## Requirements

- macOS 13 or later
- Robobloq DX Light strip connected over USB
- Only one process can control the strip at a time; quit the official DX Light app first

## Build

```bash
cd /Users/ugogo/dev/dx-light
npm run build
```

Outputs:

- Menu bar app: `dist/DX Light.app`
- CLI: `.build/release/dx-light-cli`

## CLI usage

```bash
swift run dx-light-cli list
swift run dx-light-cli info
swift run dx-light-cli off
swift run dx-light-cli on 0.5
swift run dx-light-cli brightness 0.75
swift run dx-light-cli test
```

## Menu bar app

1. Run `npm run restart` to rebuild and launch the current app bundle
2. Click the light bulb icon in the menu bar
3. Toggle power or adjust brightness
4. Enable `Open at login` if you want DX Light to launch automatically
5. Enable `Smooth transitions` if you want short fades for power, brightness, and color changes
6. Keep `Turn on when USB connects` enabled if the strip moves between machines through a KVM
7. Option+click the icon to toggle power without opening the popover

The app polls for the strip every second and reconnects automatically after sleep or USB replug. `npm run start` and `npm run restart` rebuild the app bundle before launching, so local testing uses the current source instead of a stale `dist/DX Light.app`.

`Open at login` uses macOS Login Items. If macOS asks for approval, enable DX Light in System Settings → General → Login Items.

`Smooth transitions` keeps fades short and uses a small number of device writes so the USB connection stays responsive.

`Turn on when USB connects` is useful for KVM setups: when the strip disappears from the Mac and later reconnects, DX Light marks the app state as on and sends the on command automatically. If you prefer reconnects to preserve the previous app power state, turn this off.

## Troubleshooting

Check that the strip is visible to macOS:

```bash
system_profiler SPUSBDataType | grep -i -A 8 "1a86\|robobloq"
.build/release/dx-light-cli list
```

Expected USB identifiers:

- HID: vendor `0x1A86`, product `0xFE07`
- Serial CDC fallback: vendor `0x1A86`, product `0xFE0C`

If control fails with a busy-device error, close any other app that may hold the USB interface, including the official DX Light app.

## Hardware smoke test

Run this after transport changes, before a release, or when something feels off with a connected bar:

```bash
npm run smoke
```

The script builds the CLI, lists the connected strip, then walks through on, brightness, and off checks.

For manual app validation:

1. Quit the official DX Light app and this app.
2. Run `npm run restart`.
3. Confirm the menu shows connected.
4. Toggle power from the app.
5. Change brightness and color from the app.
6. Unplug and replug USB, then confirm the menu reconnects within a few seconds.
7. With `Turn on when USB connects` enabled, confirm the strip turns on after reconnect.

If the CLI smoke test works but the app does not, first suspect a stale/running app bundle or USB ownership. If both CLI and app fail, check device discovery and whether another process has the HID interface open.

## Physical button investigation

The main bar button is not synced into app state yet. Keep physical-button experiments in debug tooling until the exact device report is confirmed:

```bash
swift run dx-light-cli debug-button /tmp/dx-light-button-debug.log
```

Close the menu app before running debug captures. The app should not hold a persistent listener while also sending control commands; that architecture can make the HID device busy and break normal on/off/color control.

## Distribution / notarization

For personal use, ad-hoc signing is enough:

```bash
codesign --force --deep --sign - "dist/DX Light.app"
```

For wider distribution:

1. Enable Developer ID signing in Xcode or `codesign`
2. Include `com.apple.security.device.usb` in entitlements ([`DXLight.entitlements`](DXLight.entitlements))
3. Notarize with `notarytool` and staple the ticket

## Architecture

- [`Sources/DXLightCore/RobobloqProtocol.swift`](Sources/DXLightCore/RobobloqProtocol.swift) — reverse-engineered `RB` packet format from the official app
- [`Sources/DXLightCore/HIDTransport.swift`](Sources/DXLightCore/HIDTransport.swift) — IOHIDManager output reports
- [`Sources/DXLightCore/SerialTransport.swift`](Sources/DXLightCore/SerialTransport.swift) — 115200 baud CDC fallback
- [`Sources/DXLightCore/LightController.swift`](Sources/DXLightCore/LightController.swift) — connection polling and state

## Out of scope (v1)

- Screen ambilight / audio sync
- BLE / wireless dongle support
- LED effects
- Physical button state sync

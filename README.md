# DX Light

A lightweight native macOS menu bar app that controls a Robobloq DX Light monitor LED strip over USB. It replaces the official Electron app for reliable on/off and brightness control.

## Requirements

- macOS 13 or later
- Robobloq DX Light strip connected over USB
- Only one process can control the strip at a time; quit the official DX Light app first

## Build

```bash
cd /Users/ugogo/dev/dx-light
swift build -c release --product dx-light-cli
./scripts/build-app.sh
```

Outputs:

- Menu bar app: `dist/DX Light.app`
- CLI: `.build/release/dx-light-cli`

## CLI usage

```bash
.build/release/dx-light-cli list
.build/release/dx-light-cli info
.build/release/dx-light-cli off
.build/release/dx-light-cli on 0.5
.build/release/dx-light-cli brightness 0.75
.build/release/dx-light-cli test
```

## Menu bar app

1. Open `dist/DX Light.app`
2. Click the light bulb icon in the menu bar
3. Toggle power or adjust brightness
4. Option+click the icon to toggle power without opening the popover

The app polls for the strip every 2 seconds and reconnects automatically after sleep or USB replug.

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
- LED effects and color picker

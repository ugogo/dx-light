import DXLightCore
import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var controller: LightController
    @ObservedObject var loginItemController: LoginItemController
    @State private var sliderValue: Double
    @State private var pickerColor: Color

    init(controller: LightController, loginItemController: LoginItemController) {
        self.controller = controller
        self.loginItemController = loginItemController
        _sliderValue = State(initialValue: controller.brightness)
        _pickerColor = State(initialValue: controller.color.swiftUIColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: controller.menuBarSymbol)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DX Light")
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Toggle(isOn: powerBinding) {
                Text(controller.isOn ? "Light is on" : "Light is off")
            }
            .toggleStyle(.switch)
            .disabled(!isConnected)

            VStack(alignment: .leading, spacing: 6) {
                Text("Brightness")
                    .font(.subheadline)
                Slider(
                    value: $sliderValue,
                    in: 0...1.0,
                    onEditingChanged: { editing in
                        if !editing {
                            controller.setBrightness(sliderValue)
                        }
                    }
                )
                Text("\(Int(sliderValue * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!isConnected || !controller.isOn)
            .onChange(of: controller.brightness) { newValue in
                if abs(sliderValue - newValue) > 0.001 {
                    sliderValue = newValue
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.subheadline)

                HStack(spacing: 10) {
                    ForEach(controller.colorPresets, id: \.name) { preset in
                        Button {
                            controller.setColor(preset.color)
                            pickerColor = preset.color.swiftUIColor
                        } label: {
                            Circle()
                                .fill(preset.color.swiftUIColor)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if controller.color == preset.color {
                                        Circle()
                                            .strokeBorder(.primary, lineWidth: 2)
                                    }
                                }
                                .overlay {
                                    if preset.name == ColorPreset.savedName {
                                        Image(systemName: "bookmark.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.9))
                                            .shadow(radius: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }

                    Spacer()

                    Button {
                        if let rgb = pickerColor.rgbColor() {
                            controller.saveColorAsPreset(rgb)
                        }
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Save current color as preset")

                    ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                        .labelsHidden()
                }
            }
            .disabled(!isConnected || !controller.isOn)
            .onChange(of: controller.color) { newValue in
                let updated = newValue.swiftUIColor
                if pickerColor.rgbColor() != newValue {
                    pickerColor = updated
                }
            }
            .onChange(of: pickerColor) { newValue in
                guard let rgb = newValue.rgbColor(), rgb != controller.color else { return }
                controller.setColor(rgb)
            }

            if case .error = controller.status {
                Text("Close any other DX Light app, check USB, then click Refresh.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle(isOn: launchAtLoginBinding) {
                Text("Open at login")
            }
            .toggleStyle(.switch)

            Toggle(isOn: smoothTransitionsBinding) {
                Text("Smooth transitions")
            }
            .toggleStyle(.switch)

            if let detail = loginItemController.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Refresh") {
                    Task { await controller.refreshConnection() }
                }
                .disabled(controller.isBusy)

                Spacer()

                Button("Quit") {
                    controller.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var powerBinding: Binding<Bool> {
        Binding(
            get: { controller.isOn },
            set: { controller.requestSetPower($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItemController.isEnabled },
            set: { loginItemController.setEnabled($0) }
        )
    }

    private var smoothTransitionsBinding: Binding<Bool> {
        Binding(
            get: { controller.smoothTransitions },
            set: { controller.setSmoothTransitions($0) }
        )
    }

    private var isConnected: Bool {
        if case .connected = controller.status {
            return true
        }
        return false
    }

    private var statusText: String {
        switch controller.status {
        case .searching:
            return "Searching for strip..."
        case .connected(let device):
            return "Connected · \(device.kind.rawValue)"
        case .error(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch controller.status {
        case .connected:
            return controller.isOn ? .yellow : .secondary
        case .searching:
            return .orange
        case .error:
            return .red
        }
    }
}

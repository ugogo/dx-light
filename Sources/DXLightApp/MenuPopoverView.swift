import DXLightCore
import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var controller: LightController
    @State private var sliderValue: Double

    init(controller: LightController) {
        self.controller = controller
        _sliderValue = State(initialValue: controller.brightness)
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

            if case .error = controller.status {
                Text("Quit the official DX Light app and restart this app if control fails.")
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

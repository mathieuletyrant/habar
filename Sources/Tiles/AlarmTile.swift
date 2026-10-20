import SwiftUI

/// Alarm panel: arm without code, disarm asks for the PIN when HA requires one (code_format set).
struct AlarmTile: View {
    @Environment(HAClient.self) private var ha
    let tile: Tile
    var card = true  // false inside the header popover, which is already a surface

    @State private var askingCode = false
    @State private var code = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        let e = ha.states[tile.entityId]
        let state = e?.state
        let disarmed = state == "disarmed"
        let color = tile.tint(e)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: tile.symbol(e))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(color.gradient))
                    .shadow(color: color.opacity(0.5), radius: 10, y: 2)
                    .symbolEffect(.pulse, isActive: state == "triggered")
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title(e)).font(.headline)
                    Text(Alarm.label(state)).font(.subheadline).foregroundStyle(color)
                        .contentTransition(.opacity)
                }
                Spacer()
            }

            if askingCode {
                HStack(spacing: 8) {
                    SecureField("Code", text: $code)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .rounded))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .glassEffect(in: .capsule)
                        .focused($focused)
                        .onSubmit(disarm)
                    Button("OK", action: disarm)
                        .buttonStyle(.glassProminent)
                        .tint(.green)
                    Button { askingCode = false; code = ""; error = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                }
                .controlSize(.large)
                .onAppear { focused = true }
                .transition(.blurReplace)
            } else {
                HStack(spacing: 8) {
                    action(L("Armer"), "lock.fill", tint: .red, active: !disarmed) { run(tile.armService) }
                    action(L("Désarmer"), "lock.open.fill", tint: .green, active: disarmed) {
                        if e?.attributes["code_format"] is String { askingCode = true } else { run("alarm_disarm") }
                    }
                }
                .controlSize(.large)
                .transition(.blurReplace)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .modifier(CardIf(on: card, tint: disarmed ? nil : color))
        .animation(.snappy, value: askingCode)
        .animation(.snappy, value: state)
    }

    @ViewBuilder
    private func action(_ title: String, _ icon: String, tint: Color, active: Bool, perform: @escaping () -> Void) -> some View {
        let button = Button(action: perform) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        if active {
            button.buttonStyle(.glassProminent).tint(tint)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private func disarm() {
        run("alarm_disarm", ["code": code])
    }

    private func run(_ service: String, _ data: [String: Any] = [:]) {
        error = nil
        Task {
            do {
                try await ha.call("alarm_control_panel", service, tile.entityId, data)
                askingCode = false
            } catch let err {
                error = err.localizedDescription
            }
            code = ""
        }
    }
}

/// Compact alarm for the header: lock + state; click opens the full controls (the AlarmTile above) in a popover.
struct AlarmBadge: View {
    @Environment(HAClient.self) private var ha
    let tile: Tile
    @State private var open = false

    var body: some View {
        let e = ha.states[tile.entityId]
        Button { open.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: Alarm.menuSymbol(e?.state))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, isActive: e?.state == "triggered")
                    .frame(width: Header.icon, height: Header.icon)  // same height as the header's round buttons
                Text(Alarm.shortLabel(e?.state)).font(.callout.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(tile.tint(e))
        }
        .buttonBorderShape(.capsule)
        .help(tile.title(e))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            AlarmTile(tile: tile, card: false)
                .environment(ha)
                .buttonBorderShape(.automatic)  // the header's buttons are circles; don't inherit that
                .frame(width: 320)
                .padding(6)
        }
    }
}

private struct CardIf: ViewModifier {
    let on: Bool
    let tint: Color?
    func body(content: Content) -> some View {
        if on { content.glassCard(26, tint: tint) } else { content }
    }
}

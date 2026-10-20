import SwiftUI

/// Small climate tile (four per row): target, current temperature, name. Click for the controls.
struct ClimateTile: View {
    @Environment(HAClient.self) private var ha
    let tile: Tile
    @State private var open = false

    var body: some View {
        let e = ha.states[tile.entityId]
        let c = ClimateState(e)
        let color = Climate.color(e?.state, action: nil)  // hue of the mode; activity sets the strength

        Button { open.toggle() } label: {
            // no icon: color is the state. Heating/cooling tints the block; idle only colors the target (mode hue).
            // The current temperature lives in the Rooms section.
            VStack(alignment: .leading, spacing: 3) {
                // no minimumScaleFactor anywhere: shrunk text has shorter lines and made tiles uneven
                Text(ClimateState.title(tile, e, ha))
                    .font(.caption.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)  // wrap ("Chambre / parents") instead of truncating
                // the big number is the target
                Text(c.off ? L("Éteint") : c.target.map(ClimateState.degrees) ?? "—")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(c.off ? AnyShapeStyle(.secondary) : c.active ? AnyShapeStyle(.primary) : AnyShapeStyle(color))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .glassCard(18, tint: c.active ? color : nil)
        }
        .buttonStyle(.pressable)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ClimateControls(tile: tile).environment(ha)
        }
    }
}

/// Popover controls: mode picker and a target stepper. Clicks move the shown target at once;
/// one set_temperature goes out once they stop.
struct ClimateControls: View {
    @Environment(HAClient.self) private var ha
    let tile: Tile
    @State private var pending: Double?
    @State private var send: Task<Void, Never>?

    var body: some View {
        let e = ha.states[tile.entityId]
        let c = ClimateState(e)
        let target = pending ?? c.target
        let mode = Binding(
            get: { e?.state ?? "off" },
            set: { m in Task { try? await ha.call("climate", "set_hvac_mode", tile.entityId, ["hvac_mode": m]) } }
        )

        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(ClimateState.title(tile, e, ha)).font(.headline).lineLimit(1)
                Text([c.current.map { L("Actuel") + " " + ClimateState.degrees($0) },
                      c.off ? nil : Climate.status(e?.state, action: c.action)].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if c.modes.count <= 4 {
                Picker(L("Mode"), selection: mode) {
                    ForEach(c.modes, id: \.self) { Text(Climate.label($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } else {
                Picker(L("Mode"), selection: mode) {
                    ForEach(c.modes, id: \.self) { Text(Climate.label($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            if !c.off, let target {
                HStack(spacing: 18) {
                    Button { adjust(target - c.step, c.range) } label: {
                        Image(systemName: "minus").font(.title3.weight(.semibold)).frame(width: 22, height: 22)
                    }
                    Text(ClimateState.degrees(target))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(minWidth: 110)
                    Button { adjust(target + c.step, c.range) } label: {
                        Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(width: 300)
        .animation(.snappy, value: target)
        .onChange(of: c.target) { _, new in
            if new == pending { pending = nil }  // HA caught up: drop the local value
        }
    }

    private func adjust(_ value: Double, _ range: ClosedRange<Double>) {
        pending = min(max(value, range.lowerBound), range.upperBound)
        send?.cancel()
        send = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let pending else { return }
            do { try await ha.call("climate", "set_temperature", tile.entityId, ["temperature": pending]) }
            catch { self.pending = nil }  // refused: show HA's value again
        }
    }
}

/// The climate attributes the tile and the controls read.
struct ClimateState {
    let off: Bool, active: Bool, action: String?, current: Double?, target: Double?
    let step: Double, range: ClosedRange<Double>, modes: [String]

    init(_ e: EntityState?) {
        let a = e?.attributes ?? [:]
        let number = { (key: String) in (a[key] as? NSNumber)?.doubleValue }
        off = e?.state == "off"
        active = ["heating", "cooling", "drying", "fan"].contains(a["hvac_action"] as? String ?? "")
        action = a["hvac_action"] as? String
        current = number("current_temperature")
        target = number("temperature")
        step = number("target_temp_step") ?? 0.5
        range = (number("min_temp") ?? 7)...(number("max_temp") ?? 35)
        modes = a["hvac_modes"] as? [String] ?? []
    }

    /// Named after its HA room ("Chambre parents" beats a truncated "Clim chambre…"), unless renamed in Settings.
    @MainActor static func title(_ tile: Tile, _ e: EntityState?, _ ha: HAClient) -> String {
        tile.name.isEmpty ? (ha.areaName(tile.entityId) ?? tile.title(e)) : tile.name
    }

    static func degrees(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1))) + "°"
    }
}

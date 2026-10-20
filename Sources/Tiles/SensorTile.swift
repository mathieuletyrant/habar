import SwiftUI

/// Control Center–style square: sensors are read-only, toggles switch on tap.
struct SensorTile: View {
    @Environment(HAClient.self) private var ha
    let tile: Tile
    var wide = false  // single tile in its section: lay out as a row instead of a big empty square

    var body: some View {
        let e = ha.states[tile.entityId]
        let isToggle = tile.kind == .toggle
        let on = isToggle && e?.isOn == true
        let tint = tile.tint(e)

        Button {
            guard isToggle else { return }
            Task { try? await ha.call("homeassistant", "toggle", tile.entityId) }
        } label: {
            let layout = wide ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            layout {
                Image(systemName: tile.symbol(e))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(on ? .white : (isToggle ? .secondary : tint))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(on ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(isToggle ? 0.12 : 0.18))))
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 1) {
                    value(e, isToggle: isToggle, on: on)
                    Text(tile.title(e))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .contentShape(.rect)
            .glassCard(22, tint: on ? tint : nil, interactive: isToggle)
        }
        .buttonStyle(.pressable)
        .animation(.snappy, value: e?.state)
    }

    @ViewBuilder
    private func value(_ e: EntityState?, isToggle: Bool, on: Bool) -> some View {
        if isToggle {
            Text(on ? L("Allumé") : L("Éteint")).font(.system(.title3, design: .rounded).weight(.semibold))
        } else if let n = e?.number {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(n)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(e?.unit ?? "").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else {
            Text(e?.display ?? "—").font(.system(.title3, design: .rounded).weight(.semibold)).lineLimit(1)
        }
    }
}

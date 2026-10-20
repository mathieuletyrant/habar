import SwiftUI

/// Live power breakdown by room (HA areas), found automatically. Click a room for its devices.
struct EnergyRooms: View {
    @Environment(HAClient.self) private var ha
    let areas: [HAClient.PowerArea]
    let other: Double  // house total not covered by any room
    @State private var expanded: String?

    private static let colors: [Color] = [.orange, .yellow, .mint, .cyan, .blue, .purple, .pink, .red, .green, .indigo]

    var body: some View {
        let scale = max(areas.map(\.watts).max() ?? 1, 1)  // biggest room = full bar
        let other = other >= 1 ? other : 0
        let total = max(areas.map(\.watts).reduce(0, +) + other, 1)
        let color = { (i: Int) in Self.colors[i % Self.colors.count] }
        let indexed = Array(areas.enumerated())
        let floors = indexed.reduce(into: [(floor: String?, rooms: [(Int, HAClient.PowerArea)])]()) { acc, pair in
            if acc.last?.floor == pair.element.floor { acc[acc.count - 1].rooms.append(pair) }
            else { acc.append((pair.element.floor, [pair])) }
        }

        VStack(alignment: .leading, spacing: 14) {
            // flow-like overview: one segment per room, same colors as the rows below
            GeometryReader { g in
                let gap: CGFloat = 2
                let parts = indexed.map { (color($0.offset), $0.element.watts) } + (other > 0 ? [(Color.gray.opacity(0.5), other)] : [])
                let usable = g.size.width - gap * CGFloat(parts.count - 1)
                let widths = parts.map { usable * $0.1 / total }
                ZStack(alignment: .leading) {
                    ForEach(parts.indices, id: \.self) { i in
                        Capsule().fill(parts[i].0.gradient)
                            .frame(width: max(widths[i], 3))
                            .offset(x: widths[..<i].reduce(0, +) + gap * CGFloat(i))
                    }
                }
                .frame(width: g.size.width, alignment: .leading)
            }
            .frame(height: 10)

            ForEach(floors.indices, id: \.self) { f in
                VStack(alignment: .leading, spacing: 10) {
                    if let floor = floors[f].floor {
                        HStack {
                            Text(floor).textCase(.uppercase)
                            Spacer()
                            Text(EntityState.formatWatts(floors[f].rooms.map(\.1.watts).reduce(0, +))).monospacedDigit()
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                    }
                    ForEach(floors[f].rooms, id: \.1.id) { i, area in
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                withAnimation(.snappy) { expanded = expanded == area.id ? nil : area.id }
                            } label: {
                                row(area.id, watts: area.watts, scale: scale, color: color(i), bold: true,
                                    chevron: expanded == area.id ? "chevron.down" : "chevron.right")
                            }
                            .buttonStyle(.pressable)

                            if expanded == area.id {
                                VStack(spacing: 6) {
                                    ForEach(area.items) { item in
                                        row(item.name, watts: item.watts, scale: scale, color: color(i).opacity(0.6), bold: false, chevron: nil)
                                    }
                                }
                                .padding(.leading, 12)
                                .transition(.blurReplace)
                            }
                        }
                    }
                }
            }

            if other > 0 {
                row(L("Autres"), watts: other, scale: scale, color: .gray.opacity(0.5), bold: true, chevron: nil)
                    .foregroundStyle(.secondary)
                    .help(L("Total maison moins la somme des pièces"))
            }
        }
        .padding(14)
        .glassCard(24)
    }

    private func row(_ name: String, watts: Double, scale: Double, color: Color, bold: Bool, chevron: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(bold ? .callout.weight(.semibold) : .caption)
                    .foregroundStyle(bold ? .primary : .secondary)
                    .lineLimit(1)
                Spacer()
                Text(EntityState.formatWatts(watts))
                    .font((bold ? Font.callout : .caption).monospacedDigit())
                    .foregroundStyle(bold ? .primary : .secondary)
                    .contentTransition(.numericText())
                if let chevron {
                    Image(systemName: chevron).font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 10)
                }
            }
            Capsule()
                .fill(.quaternary)
                .frame(height: bold ? 6 : 4)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(color.gradient).frame(width: g.size.width * min(watts / scale, 1))
                    }
                }
        }
        .contentShape(.rect)
    }
}

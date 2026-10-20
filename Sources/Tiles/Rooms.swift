import SwiftUI

/// Every HA room as an aligned table: climate (sensors set on the area) and live power.
/// A stacked bar on top shows where the power goes; each room's dot matches its segment. Click a room for its devices.
struct RoomsView: View {
    let areas: [HAClient.Room]
    let other: Double?  // house total not covered by any room; nil without a house total sensor
    @State private var expanded: String?


    var body: some View {
        let total = max(areas.map(\.watts).reduce(0, +) + (other ?? 0), 1)
        // golden-ratio hue steps: every room gets its own hue and neighbours stay far apart, whatever the room count
        let color = { (i: Int) in
            Color(hue: (Double(i) * 0.382).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.95)
        }
        let indexed = Array(areas.enumerated())
        let floors = indexed.reduce(into: [(floor: String?, rooms: [(Int, HAClient.Room)])]()) { acc, pair in
            if acc.last?.floor == pair.element.floor { acc[acc.count - 1].rooms.append(pair) }
            else { acc.append((pair.element.floor, [pair])) }
        }

        VStack(alignment: .leading, spacing: 14) {
            // where the power goes: one segment per room, same color as the room's dot
            GeometryReader { g in
                let gap: CGFloat = 2
                let parts = indexed.filter { $0.element.watts >= 1 }.map { (color($0.offset), $0.element.watts) }
                    + ((other ?? 0) >= 1 ? [(Color.gray.opacity(0.5), other ?? 0)] : [])
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
            .frame(height: 8)

            VStack(alignment: .leading, spacing: 9) {
                columns(Color.clear, Image(systemName: "thermometer.medium"), Image(systemName: "humidity.fill"),
                        Image(systemName: "bolt.fill"), Color.clear)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)

                ForEach(floors.indices, id: \.self) { f in
                    if let floor = floors[f].floor {
                        Text(floor)
                            .textCase(.uppercase)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                    ForEach(floors[f].rooms, id: \.1.id) { i, room in
                        roomRow(room, color: color(i))
                        if expanded == room.id {
                            ForEach(room.items) { item in
                                columns(Text(item.name).lineLimit(1).padding(.leading, 14), Text(""), Text(""),
                                        Text(EntityState.formatWatts(item.watts)), Color.clear)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .transition(.blurReplace)
                            }
                        }
                    }
                }

                if let other, other >= 1 {  // only when the house total and the rooms really differ
                    columns(Text(L("Autres")).padding(.leading, 14), Text(""), Text(""),
                            Text(EntityState.formatWatts(other)).contentTransition(.numericText()), Color.clear)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help(L("Total maison moins la somme des pièces"))
                }
            }
            .monospacedDigit()
        }
        .padding(14)
        .glassCard(24)
    }

    // fixed-width value columns keep every row aligned; the name takes whatever is left
    private static let spacing: CGFloat = 8, tempWidth: CGFloat = 44, humidityWidth: CGFloat = 38,
                       wattsWidth: CGFloat = 58, chevronWidth: CGFloat = 8

    private func columns(_ name: some View, _ temp: some View, _ humidity: some View, _ watts: some View,
                         _ chevron: some View) -> some View {
        HStack(spacing: Self.spacing) {
            name.frame(maxWidth: .infinity, alignment: .leading)
            temp.frame(width: Self.tempWidth, alignment: .trailing)
            humidity.frame(width: Self.humidityWidth, alignment: .trailing)
            watts.frame(width: Self.wattsWidth, alignment: .trailing)
            chevron.frame(width: Self.chevronWidth)
        }
    }

    private func roomRow(_ room: HAClient.Room, color: Color) -> some View {
        columns(
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(room.id).font(.callout.weight(.semibold)).lineLimit(1)
            },
            Text(room.temperature.map { $0.formatted(.number.precision(.fractionLength(1))) + "°" } ?? ""),
            Text(room.humidity.map { $0.formatted(.number.precision(.fractionLength(0))) + " %" } ?? "")
                .foregroundStyle(.secondary),
            // blank under 1 W: the row itself stays, so the height doesn't jump
            Text(room.watts >= 1 ? EntityState.formatWatts(room.watts) : "").contentTransition(.numericText()),
            Image(systemName: expanded == room.id ? "chevron.down" : "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .opacity(room.items.isEmpty ? 0 : 1)
        )
        .font(.callout)
        .contentShape(.rect)
        .onTapGesture {
            guard !room.items.isEmpty else { return }
            withAnimation(.snappy) { expanded = expanded == room.id ? nil : room.id }
        }
    }
}

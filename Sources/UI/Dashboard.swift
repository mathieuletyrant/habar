import SwiftUI

struct Dashboard: View {
    @Environment(HAClient.self) private var ha
    @State private var dropTarget: DashSection?

    var body: some View {
        // fill the screen before scrolling (minus header, paddings and menu bar)
        AutoScroll(maxHeight: (NSScreen.main?.visibleFrame.height ?? 800) - 120) {
            VStack(spacing: 18) {
                if ha.tiles.isEmpty {
                    ContentUnavailableView(L("Aucune tuile"), systemImage: "square.grid.2x2",
                                           description: Text(L("Ajoute des entités via ⚙︎")))
                }
                ForEach(ha.sectionOrder, id: \.self) { s in
                    section(s)
                        .dropDestination(for: String.self) { items, _ in
                            guard let src = items.first.flatMap(DashSection.init) else { return false }
                            withAnimation(.snappy) { ha.moveSection(src, to: s) }
                            return true
                        } isTargeted: { dropTarget = $0 ? s : (dropTarget == s ? nil : dropTarget) }
                        .overlay {
                            if dropTarget == s {
                                RoundedRectangle(cornerRadius: 26).strokeBorder(.tint, lineWidth: 2).padding(-4)
                            }
                        }
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func section(_ s: DashSection) -> some View {
        let tiles = { (k: TileKind) in ha.tiles.filter { $0.kind == k && $0.inDashboard } }
        switch s {
        case .sensors:
            let t = tiles(.sensor)
            if !t.isEmpty { TileSection(title: L("Capteurs"), icon: "gauge.with.dots.needle.50percent", drag: s) { grid(t) } }
        case .toggles:
            let t = tiles(.toggle)
            if !t.isEmpty { TileSection(title: L("Contrôles"), icon: "switch.2", drag: s) { grid(t) } }
        case .climate:
            let t = tiles(.climate)
            if !t.isEmpty {
                TileSection(title: L("Climat"), icon: "thermometer.sun.fill", drag: s) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: min(t.count, 4)), spacing: 8) {
                        ForEach(t) { ClimateTile(tile: $0) }
                    }
                }
            }
        case .cameras:
            let t = tiles(.camera)
            if !t.isEmpty { TileSection(title: L("Caméras"), icon: "video.fill", drag: s) { CameraGrid(tiles: t) } }
        case .security:
            let t = Array(tiles(.alarm).dropFirst())  // the first alarm lives in the header (AlarmBadge)
            if !t.isEmpty { TileSection(title: L("Sécurité"), icon: "shield.fill", drag: s) { ForEach(t) { AlarmTile(tile: $0) } } }
        case .energy:
            let rooms = ha.showEnergy ? ha.rooms() : []
            // whole-house total = first power sensor shown as a tile; the gap with the rooms is "Autres"
            let houseTotal = ha.tiles.lazy.compactMap { ha.states[$0.entityId] }.first { $0.deviceClass == "power" }?.watts
            let roomsSum = rooms.map(\.watts).reduce(0, +)
            if !rooms.isEmpty {
                TileSection(title: L("Pièces"), icon: "house.fill",
                            trailing: EntityState.formatWatts(max(houseTotal ?? 0, roomsSum)), drag: s) {
                    RoomsView(areas: rooms, other: houseTotal.map { max($0 - roomsSum, 0) })
                }
            }
        }
    }

    /// 2 columns for 2 or 4 tiles, otherwise 3: rows stay full and even.
    private func grid(_ tiles: [Tile]) -> some View {
        let cols = tiles.count == 2 || tiles.count == 4 ? 2 : min(tiles.count, 3)
        return GlassEffectContainer(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: cols), spacing: 10) {
                ForEach(tiles) { SensorTile(tile: $0, wide: cols == 1) }
            }
        }
    }
}

struct Header: View {
    @Environment(HAClient.self) private var ha
    @Binding var page: Page

    /// One box for every header symbol: their natural sizes differ, which made the round buttons uneven.
    static let icon: CGFloat = 18

    private var title: String {
        switch page {
        case .dashboard: ha.homeName.isEmpty ? L("Maison") : ha.homeName
        case .inbox: "Notifications"
        case .settings: L("Réglages")
        case .picker: L("Ajouter")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .contentTransition(.opacity)
                HStack(spacing: 5) {
                    Circle().fill(dot).frame(width: 6, height: 6).shadow(color: dot, radius: 3)
                    Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if page == .dashboard, let alarm = ha.tiles.first(where: { $0.kind == .alarm && $0.inDashboard }) {
                        AlarmBadge(tile: alarm)
                    }
                    let count = page == .inbox ? 0 : ha.badgeCount
                    Button { page = page == .inbox ? .dashboard : .inbox } label: {
                        HStack(spacing: 4) {
                            Image(systemName: page == .inbox ? "checkmark" : (count > 0 ? "bell.badge.fill" : "bell"))
                                .symbolRenderingMode(count > 0 ? .multicolor : .monochrome)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: Header.icon, height: Header.icon)
                            if count > 0 {
                                Text("\(count)").font(.callout.weight(.semibold)).monospacedDigit()
                            }
                        }
                    }
                    .buttonBorderShape(count > 0 ? .capsule : .circle)
                    .help("Notifications")
                    Button {
                        page = switch page {
                        case .picker: .settings
                        case .settings: .dashboard
                        default: .settings
                        }
                    } label: {
                        Image(systemName: page == .picker ? "chevron.left" : page == .settings ? "checkmark" : "slider.horizontal.3")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: Header.icon, height: Header.icon)
                    }
                    .help(L("Réglages"))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
            }
        }
    }

    private var dot: Color {
        switch ha.status {
        case .connected: .green
        case .connecting: .orange
        case .offline: .gray
        case .error: .red
        }
    }

    private var label: String {
        switch ha.status {
        case .connected: L("Connecté")
        case .connecting: L("Connexion…")
        case .offline: L("Non configuré")
        case .error(let m): m
        }
    }
}

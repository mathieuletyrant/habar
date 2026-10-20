import SwiftUI

/// Full page to add/remove entities: search, filter by type, one tap toggles a tile.
struct EntityPicker: View {
    @Environment(HAClient.self) private var ha
    @State private var search = ""
    @State private var filter: TileKind?
    @FocusState private var focused: Bool

    var body: some View {
        let q = search.lowercased()
        let added = Set(ha.tiles.map(\.entityId))
        let results = ha.allEntities.filter { e in
            (filter == nil || TileKind.guess(e.id) == filter)
                && (q.isEmpty || e.name.lowercased().contains(q) || e.id.lowercased().contains(q))
        }

        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Rechercher une entité"), text: $search)
                    .textFieldStyle(.plain)
                    .focused($focused)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .glassEffect(in: .capsule)

            HStack(spacing: 6) {
                chip(nil, L("Tout"))
                ForEach(TileKind.allCases) { chip($0, $0.plural) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(results) { row($0, added: added.contains($0.id)) }
                }
            }
            .scrollIndicators(.never)
            .frame(height: 420)
            .overlay {
                if ha.allEntities.isEmpty { ProgressView() }
                else if results.isEmpty { ContentUnavailableView.search(text: search) }
            }
        }
        .onAppear {
            focused = true
            Task { await ha.loadEntities() }
        }
    }

    private func chip(_ kind: TileKind?, _ label: String) -> some View {
        let selected = filter == kind
        return Button { withAnimation(.snappy) { filter = kind } } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(selected ? .regular.tint(.accentColor) : .regular, in: .capsule)
        }
        .buttonStyle(.pressable)
    }

    private func row(_ ent: EntityRef, added: Bool) -> some View {
        let tile = Tile(entityId: ent.id, kind: .guess(ent.id))
        let tint = tile.tint(ent.state)

        return Button { withAnimation(.snappy) { ha.toggleTile(for: ent.id) } } label: {
            HStack(spacing: 12) {
                Image(systemName: tile.symbol(ent.state))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(ent.name).font(.callout).lineLimit(1)
                    Text(ent.id).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(ent.state.display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(added ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(added ? RoundedRectangle(cornerRadius: 14).fill(.green.opacity(0.1)) : nil)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }
}

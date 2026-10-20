import SwiftUI

/// All cameras visible at once: 2-column grid, click one to enlarge it full width.
struct CameraGrid: View {
    let tiles: [Tile]
    @State private var focused: UUID?
    @Namespace private var ns

    var body: some View {
        let big = tiles.count == 1 ? tiles.first : tiles.first { $0.id == focused }
        let small = tiles.filter { $0.id != big?.id }

        VStack(spacing: 10) {
            if let big {
                Button { toggle(big) } label: { CameraTile(tile: big, height: 198) }
                    .buttonStyle(.pressable)
                    .overlay(alignment: .topLeading) {
                        if tiles.count > 1 {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.caption.weight(.bold))
                                .padding(8)
                                .glassEffect(in: .circle)
                                .padding(10)
                                .allowsHitTesting(false)
                        }
                    }
                    .help(L("Réduire"))
                    .matchedGeometryEffect(id: big.id, in: ns)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(small) { t in
                    Button { toggle(t) } label: { CameraTile(tile: t, height: 96) }
                        .buttonStyle(.pressable)
                        .help(L("Agrandir"))
                        .matchedGeometryEffect(id: t.id, in: ns)
                }
            }
        }
    }

    private func toggle(_ t: Tile) {
        guard tiles.count > 1 else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { focused = focused == t.id ? nil : t.id }
    }
}

/// Camera snapshot; HAClient refreshes it in the background.
struct CameraTile: View {
    @Environment(HAClient.self) private var ha
    let tile: Tile
    let height: CGFloat

    var body: some View {
        let e = ha.states[tile.entityId]
        let compact = height < 150

        Color.clear
            .frame(height: height)
            .overlay {
                if let img = ha.cameraImages[tile.entityId] {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary).overlay(ProgressView().controlSize(.small))
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .frame(height: compact ? 44 : 70)
            }
            .overlay(alignment: .bottomLeading) {
                Label(tile.title(e), systemImage: tile.symbol(e))
                    .font(compact ? .caption2.weight(.semibold) : .callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(compact ? 8 : 12)
            }
            .overlay(alignment: .topTrailing) {
                Circle().fill(.red).frame(width: 7, height: 7)
                    .shadow(color: .red, radius: 4)
                    .padding(compact ? 8 : 12)
                    .opacity(ha.cameraImages[tile.entityId] == nil ? 0 : 1)
            }
            .clipShape(.rect(cornerRadius: compact ? 16 : 22))
            .overlay(RoundedRectangle(cornerRadius: compact ? 16 : 22).strokeBorder(.white.opacity(0.12)))
            .contentShape(.rect)
    }
}

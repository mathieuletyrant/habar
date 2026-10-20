import SwiftUI

extension View {
    /// Liquid Glass surface used by every tile.
    func glassCard(_ radius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.3)) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: .rect(cornerRadius: radius))
    }
}

/// Titled group: keeps every tile type in its own section for a consistent rhythm.
struct TileSection<Content: View>: View {
    let title: String
    let icon: String
    var trailing: String?
    var drag: DashSection?  // set = header can be dragged to reorder sections
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon).textCase(.uppercase)
                Spacer()
                if let trailing { Text(trailing).monospacedDigit().contentTransition(.numericText()) }
                if drag != nil { Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .contentShape(.rect)
            .draggable(drag?.rawValue ?? "")
            .help(drag == nil ? "" : L("Glisser pour réordonner"))
            content
        }
    }
}

/// ScrollView that hugs its content and only scrolls past `maxHeight`
/// (a plain ScrollView has no intrinsic height inside a MenuBarExtra window).
struct AutoScroll<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(height, maxHeight))
    }
}

/// iOS Settings–style group: rows separated by inset dividers on one glass card.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { i in
                    rows[i]
                    if i < rows.count - 1 { Divider().padding(.leading, 50) }
                }
            }
        }
        .glassCard(16)
    }
}

/// Colored rounded-square icon, title, optional subtitle, trailing control.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

extension SettingsRow {
    /// Row with a trailing switch.
    init(icon: String, color: Color, title: String, subtitle: String? = nil, isOn: Binding<Bool>) where Trailing == AnyView {
        self.init(icon: icon, color: color, title: title, subtitle: subtitle) {
            AnyView(Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small))
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

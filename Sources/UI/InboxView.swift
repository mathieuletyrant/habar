import SwiftUI

/// HA persistent notifications + available updates. Click a row to expand it.
struct InboxView: View {
    @Environment(HAClient.self) private var ha

    var body: some View {
        let updates = ha.availableUpdates

        AutoScroll(maxHeight: 560) {
            VStack(spacing: 18) {
                if ha.notifications.isEmpty && updates.isEmpty {
                    ContentUnavailableView(L("Tout est calme"), systemImage: "bell.slash",
                                           description: Text(L("Aucune notification ni mise à jour")))
                }
                if !ha.notifications.isEmpty {
                    TileSection(title: "Notifications", icon: "bell.fill") {
                        ForEach(ha.notifications) { NotificationRow(n: $0) }
                        if ha.notifications.count > 1 {
                            Button(L("Tout effacer")) {
                                Task { for n in ha.notifications { await ha.dismiss(n) } }
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                if !updates.isEmpty {
                    TileSection(title: L("Mises à jour"), icon: "arrow.down.circle.fill") {
                        ForEach(updates, id: \.id) { UpdateRow(id: $0.id, e: $0.state) }
                    }
                }
            }
            .padding(2)
        }
        .animation(.snappy, value: ha.notifications.map(\.id))
    }
}

private func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(s)
}

private struct RowIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(color.gradient))
    }
}

private struct NotificationRow: View {
    @Environment(HAClient.self) private var ha
    let n: HANotification
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(symbol: "bell.fill", color: .blue)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(n.title).font(.callout.weight(.semibold)).lineLimit(expanded ? nil : 1)
                    Spacer(minLength: 4)
                    if let d = n.created {
                        Text(d, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(markdown(n.message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if expanded {
                    Button(L("Effacer"), systemImage: "xmark") { Task { await ha.dismiss(n) } }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .glassCard(20)
        .transition(.blurReplace)
    }
}

private struct UpdateRow: View {
    @Environment(HAClient.self) private var ha
    let id: String
    let e: EntityState
    @State private var expanded = false
    @State private var notes: String?

    var body: some View {
        let title = e.attributes["title"] as? String ?? e.name ?? id
        let installed = e.attributes["installed_version"] as? String ?? "?"
        let latest = e.attributes["latest_version"] as? String ?? "?"
        let busy = (e.attributes["in_progress"] as? NSNumber)?.boolValue == true  // bool, or a % on older HA
        let summary = e.attributes["release_summary"] as? String
        let releaseURL = (e.attributes["release_url"] as? String).flatMap(URL.init(string:))

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RowIcon(symbol: "arrow.down", color: .purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(expanded ? nil : 1)
                    Text("\(installed) → \(latest)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L("Installer")) { Task { try? await ha.call("update", "install", id) } }
                        .buttonStyle(.glassProminent)
                        .tint(.purple)
                        .controlSize(.small)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let text = notes ?? summary {
                        Text(markdown(text))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(20)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(L("Pas de notes de version")).font(.caption).foregroundStyle(.tertiary)
                    }
                    if let releaseURL {
                        Link(destination: releaseURL) {
                            Label(L("Notes complètes"), systemImage: "arrow.up.right.square")
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .transition(.blurReplace)
            }
        }
        .padding(12)
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .glassCard(20)
        .task(id: expanded) {
            if expanded, notes == nil, e.attributes["supported_features"].map({ ($0 as? Int ?? 0) & 16 != 0 }) == true {
                notes = await ha.releaseNotes(id)  // feature 16 = RELEASE_NOTES
            }
        }
    }
}

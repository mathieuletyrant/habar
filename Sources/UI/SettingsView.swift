import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(HAClient.self) private var ha
    @Binding var page: Page
    @State private var url = ""
    @State private var token = ""
    @State private var expanded: UUID?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var ha = ha

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(L("Général")) {
                    SettingsGroup {
                        SettingsRow(icon: "circle.lefthalf.filled", color: .indigo, title: L("Thème")) {
                            Picker(L("Thème"), selection: $ha.appearance) {
                                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                        SettingsRow(icon: "globe", color: .blue, title: L("Langue")) {
                            Picker(L("Langue"), selection: Bindable(Lang.shared).current) {
                                ForEach(Language.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }

                section(L("Entités")) {
                    SettingsGroup {
                        ForEach($ha.tiles) { $tile in
                            TileRow(tile: $tile, expanded: $expanded)
                        }
                    }
                    HStack(spacing: 12) {
                        Label(L("Tableau de bord"), systemImage: "square.grid.2x2")
                        Label(L("Barre de menu"), systemImage: "menubar.rectangle")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    Button { page = .picker } label: {
                        Label(L("Ajouter des entités"), systemImage: "plus")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(ha.status != .connected)
                }

                section(L("Affichage")) {
                    SettingsGroup {
                        SettingsRow(icon: "house.fill", color: .yellow, title: L("Pièces"),
                                    subtitle: L("Température, humidité et puissance de chaque pièce"), isOn: $ha.showEnergy)
                        SettingsRow(icon: "house.fill", color: .blue, title: L("Icône maison"),
                                    subtitle: L("Barre de menu"), isOn: $ha.menuShowHouse)
                        SettingsRow(icon: "bell.badge.fill", color: .red, title: L("Compteur de notifications"),
                                    subtitle: L("Barre de menu"), isOn: $ha.menuShowBadge)
                    }
                }

                section(L("Notifications sur le Mac")) {
                    if ha.notificationsBlocked {
                        SettingsGroup {
                            SettingsRow(icon: "exclamationmark.triangle.fill", color: .red,
                                        title: L("Notifications bloquées par macOS"), subtitle: L("Réglages Système → Notifications → HABar")) {
                                Button(L("Ouvrir")) {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            }
                        }
                    }
                    SettingsGroup {
                        ForEach(ha.notifyServices) { service in
                            SettingsRow(icon: service.icon, color: service.icon == "bell.fill" ? .gray : .blue,
                                        title: service.name, subtitle: "notify.\(service.id)", isOn: Binding(
                                            get: { ha.mirrorNotify.contains(service.id) },
                                            set: { on in
                                                if on { ha.mirrorNotify.append(service.id) } else { ha.mirrorNotify.removeAll { $0 == service.id } }
                                            }))
                        }
                        SettingsRow(icon: "bell.and.waves.left.and.right.fill", color: .orange, title: L("Notification de test")) {
                            Button(L("Envoyer")) {
                                ha.requestNotificationPermission()
                                ha.postNotification(title: "HABar", body: L("Les notifications fonctionnent ✓"))
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                    .task {
                        await ha.loadNotifyServices()
                        await ha.refreshNotificationStatus()
                    }
                    Text(L("Les notifications envoyées par tes automatisations aux services cochés s'affichent aussi sur ce Mac."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }

                section(L("Connexion")) {
                    SettingsGroup {
                        SettingsRow(icon: "globe", color: .blue, title: L("Serveur")) {
                            TextField("ha.exemple.com", text: $url)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                        SettingsRow(icon: "key.fill", color: .gray, title: "Token") {
                            SecureField(ha.token.isEmpty ? L("Token longue durée") : L("Enregistré"), text: $token)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                        }
                        SettingsRow(icon: "power", color: .green, title: L("Lancer au démarrage"), isOn: $launchAtLogin)
                    }
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                    if url != ha.url || !token.isEmpty || ha.status != .connected {
                        Button {
                            ha.url = url
                            if !token.isEmpty { ha.token = token; token = "" }
                            ha.connect()
                        } label: {
                            Text(L("Connecter")).font(.callout.weight(.semibold)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                }
            }
            .padding(2)
        }
        .safeAreaInset(edge: .bottom) {
            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Label(L("Quitter HABar"), systemImage: "power").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .scrollIndicators(.never)
        .frame(height: 540)
        .onAppear { url = ha.url }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 6)
            content()
        }
    }
}

struct TileRow: View {
    @Environment(HAClient.self) private var ha
    @Binding var tile: Tile
    @Binding var expanded: UUID?

    var body: some View {
        let e = ha.states[tile.entityId]
        let open = expanded == tile.id

        VStack(alignment: .leading, spacing: 0) {
            // whole row expands the editor; the two placement toggles are separate buttons on top
            SettingsRow(icon: tile.symbol(e), color: tile.tint(e), title: tile.title(e), subtitle: tile.kind.label) {
                HStack(spacing: 6) {
                    placement("square.grid.2x2", L("Tableau de bord"), $tile.inDashboard)
                    if tile.kind != .camera {
                        placement("menubar.rectangle", L("Barre de menu"), $tile.inMenuBar)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .padding(.leading, 4)
                }
            }
            .contentShape(.rect)
            .onTapGesture { withAnimation(.snappy) { expanded = open ? nil : tile.id } }

            if open {
                TileEditor(tile: $tile)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.blurReplace)
            }
        }
    }

    /// Small on/off pill: accent-filled when the tile shows in that place.
    private func placement(_ icon: String, _ help: String, _ isOn: Binding<Bool>) -> some View {
        Button { withAnimation(.snappy) { isOn.wrappedValue.toggle() } } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? .white : .secondary)
                .frame(width: 28, height: 22)
                .background(isOn.wrappedValue ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary),
                            in: .capsule)
        }
        .buttonStyle(.pressable)
        .help(help)
    }
}

struct TileEditor: View {
    @Environment(HAClient.self) private var ha
    @Binding var tile: Tile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(L("Nom")) {
                TextField(L("Nom"), text: $tile.name, prompt: Text(ha.states[tile.entityId]?.name ?? L("Nom")))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
            }
            HStack {
                field("Type") {
                    Picker("Type", selection: $tile.kind) {
                        ForEach(TileKind.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
                if tile.kind == .alarm {
                    field(L("Armer en")) {
                        Picker(L("Armer en"), selection: $tile.armService) {
                            Text(L("Absent")).tag("alarm_arm_away")
                            Text(L("Présent")).tag("alarm_arm_home")
                            Text(L("Nuit")).tag("alarm_arm_night")
                        }
                        .labelsHidden()
                    }
                }
            }

            field(L("Icône")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(Tile.suggestedIcons, id: \.self) { s in
                        Button { tile.icon = tile.icon == s ? "" : s } label: {
                            Image(systemName: s)
                                .frame(width: 30, height: 30)
                                .background(tile.icon == s ? AnyShapeStyle(tile.tint(nil).opacity(0.3)) : AnyShapeStyle(.clear),
                                            in: .rect(cornerRadius: 7))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if tile.kind != .alarm {
                field(L("Couleur")) {
                    HStack(spacing: 8) {
                        swatch("", AnyShapeStyle(.quaternary))
                        ForEach(Tile.palette, id: \.name) { swatch($0.name, AnyShapeStyle($0.color)) }
                    }
                }
            }

            HStack(spacing: 8) {
                Button { ha.move(tile, by: -1) } label: { Image(systemName: "arrow.up") }
                Button { ha.move(tile, by: 1) } label: { Image(systemName: "arrow.down") }
                Spacer()
                Button(role: .destructive) {
                    let id = tile.id
                    ha.tiles.removeAll { $0.id == id }
                } label: {
                    Label(L("Retirer"), systemImage: "trash")
                }
                .tint(.red)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func swatch(_ name: String, _ style: AnyShapeStyle) -> some View {
        Button { tile.color = name } label: {
            Circle().fill(style)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(.primary, lineWidth: tile.color == name ? 2 : 0).padding(-3))
                .overlay { if name.isEmpty { Text("A").font(.system(size: 9, weight: .bold)) } }
        }
        .buttonStyle(.plain)
        .help(name.isEmpty ? "Auto" : name)
    }
}

import AppKit
import Observation
import os

struct HAError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private let log = Logger(subsystem: "com.mathieuletyrant.habar", category: "ha")

/// One persistent WebSocket to Home Assistant. States are pushed (subscribe_entities), never polled.
@MainActor @Observable
final class HAClient {
    enum Status: Equatable { case offline, connecting, connected, error(String) }

    var url = UserDefaults.standard.string(forKey: "url") ?? "" {
        didSet { UserDefaults.standard.set(url, forKey: "url") }
    }
    var token = Keychain.get() {
        didSet { Keychain.set(token) }
    }
    var tiles: [Tile] = HAClient.loadTiles() {
        didSet { saveTiles(); resubscribe() }
    }
    var appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .auto {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            NSApp.appearance = appearance.ns
        }
    }
    var homeName = ""  // HA's location name; the header falls back to L("Maison")
    var sectionOrder: [DashSection] = {
        let saved = (UserDefaults.standard.stringArray(forKey: "sectionOrder") ?? []).compactMap(DashSection.init)
        return saved + DashSection.allCases.filter { !saved.contains($0) }  // sections added later go last
    }() {
        didSet { UserDefaults.standard.set(sectionOrder.map(\.rawValue), forKey: "sectionOrder") }
    }
    var showEnergy = UserDefaults.standard.object(forKey: "showEnergy") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showEnergy, forKey: "showEnergy"); resubscribe() }
    }
    var menuShowHouse = UserDefaults.standard.object(forKey: "menuShowHouse") as? Bool ?? true {
        didSet { UserDefaults.standard.set(menuShowHouse, forKey: "menuShowHouse") }
    }
    var menuShowBadge = UserDefaults.standard.object(forKey: "menuShowBadge") as? Bool ?? true {
        didSet { UserDefaults.standard.set(menuShowBadge, forKey: "menuShowBadge") }
    }

    var states: [String: EntityState] = [:]
    var cameraImages: [String: NSImage] = [:]
    var allEntities: [EntityRef] = []
    var notifications: [HANotification] = []
    var status: Status = .offline
    var isOpen = false {
        didSet { if isOpen != oldValue { startCameraLoop() } }
    }

    @ObservationIgnored private var ws: URLSessionWebSocketTask?
    @ObservationIgnored private var nextId = 1
    @ObservationIgnored private var pending: [Int: CheckedContinuation<Any?, Error>] = [:]
    @ObservationIgnored private var subId: Int?
    @ObservationIgnored private var notifSubId: Int?
    @ObservationIgnored private var subscribed: Set<String> = []
    private var updateIds: Set<String> = []  // observed: badgeCount depends on it
    private var powerIds: Set<String> = []
    private var areaByEntity: [String: String] = [:]
    private var floorByArea: [String: (name: String, level: Int)] = [:]
    private var energyDevices: [EnergyDevice] = []
    @ObservationIgnored private var cameraLoop: Task<Void, Never>?
    @ObservationIgnored private let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "com.mathieuletyrant.habar")

    init() {
        NSApplication.shared.appearance = appearance.ns
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.connect() }
        }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        for t in tiles where t.kind == .camera {
            cameraImages[t.entityId] = NSImage(contentsOf: cacheFile(t.entityId))
        }
        connect()
        startCameraLoop()
    }

    var baseURL: URL? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        return URL(string: s)
    }

    /// Update entities with a new version available (state "on").
    var availableUpdates: [(id: String, state: EntityState)] {
        updateIds.sorted().compactMap { id in states[id].flatMap { $0.state == "on" ? (id, $0) : nil } }
    }

    var badgeCount: Int { notifications.count + availableUpdates.count }

    // MARK: - Connection

    func connect() {
        let old = ws
        ws = nil
        old?.cancel(with: .goingAway, reason: nil)
        failPending()
        guard let base = baseURL, !token.isEmpty,
              var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            status = .offline
            return
        }
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        c.path = "/api/websocket"
        guard let wsURL = c.url else { status = .error(L("URL invalide")); return }

        let task = URLSession.shared.webSocketTask(with: wsURL)
        task.maximumMessageSize = 64 << 20  // get_states can exceed the 1 MB default
        ws = task
        status = .connecting
        task.resume()
        Task { await receiveLoop(task) }
    }

    func reconnectIfNeeded() {
        if status != .connected && status != .connecting { connect() }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while ws === task {
            do {
                guard case .string(let text) = try await task.receive(),
                      let m = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
                else { continue }
                handle(m)
            } catch {
                guard ws === task else { return }
                status = .error(error.localizedDescription)
                try? await Task.sleep(for: .seconds(3))
                if ws === task { connect() }
                return
            }
        }
    }

    private func handle(_ m: [String: Any]) {
        switch m["type"] as? String {
        case "auth_required":
            send(["type": "auth", "access_token": token])
        case "auth_ok":
            status = .connected
            subscribed = []
            subId = nil
            resubscribe()
            let nid = takeId()
            notifSubId = nid
            send(["id": nid, "type": "persistent_notification/subscribe"])
            Task {
                if let c = try? await request(["type": "get_config"]) as? [String: Any],
                   let name = c["location_name"] as? String { homeName = name }
                await loadEntities()  // also discovers update.* and power entities to watch
                await loadAreas()
                await loadEnergyPrefs()
            }
        case "auth_invalid":
            let old = ws
            ws = nil
            old?.cancel()
            status = .error(L("Token invalide"))
        case "result":
            guard let id = m["id"] as? Int, let c = pending.removeValue(forKey: id) else { return }
            if m["success"] as? Bool == true {
                c.resume(returning: m["result"])
            } else {
                let msg = (m["error"] as? [String: Any])?["message"] as? String
                c.resume(throwing: HAError(msg ?? L("Erreur Home Assistant")))
            }
        case "event":
            guard let ev = m["event"] as? [String: Any] else { return }
            let id = m["id"] as? Int
            if id == subId { apply(ev) } else if id == notifSubId { applyNotifications(ev) }
        default:
            break
        }
    }

    /// Applies a compressed subscribe_entities diff: a = added, c = changed, r = removed.
    private func apply(_ ev: [String: Any]) {
        if let added = ev["a"] as? [String: [String: Any]] {
            for (id, v) in added {
                states[id] = EntityState(state: v["s"] as? String ?? "", attributes: v["a"] as? [String: Any] ?? [:])
            }
        }
        if let changed = ev["c"] as? [String: [String: Any]] {
            for (id, diff) in changed {
                var e = states[id] ?? EntityState(state: "", attributes: [:])
                if let plus = diff["+"] as? [String: Any] {
                    if let s = plus["s"] as? String { e.state = s }
                    if let a = plus["a"] as? [String: Any] { e.attributes.merge(a) { $1 } }
                }
                if let minus = diff["-"] as? [String: Any], let keys = minus["a"] as? [String] {
                    keys.forEach { e.attributes[$0] = nil }
                }
                states[id] = e
            }
        }
        (ev["r"] as? [String])?.forEach { states[$0] = nil }
    }

    private func applyNotifications(_ ev: [String: Any]) {
        let items = ev["notifications"] as? [String: [String: Any]] ?? [:]
        switch ev["type"] as? String {
        case "removed":
            notifications.removeAll { items[$0.id] != nil }
            return
        case "current":
            notifications = []
        default:
            break
        }
        for (id, n) in items {
            notifications.removeAll { $0.id == id }
            notifications.append(HANotification(id: id, raw: n))
        }
        notifications.sort { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    }

    private func resubscribe() {
        var ids = Set(tiles.map(\.entityId)).union(updateIds)
        if showEnergy { ids.formUnion(powerIds) }
        guard status == .connected, ids != subscribed else { return }
        if let subId { send(["id": takeId(), "type": "unsubscribe_events", "subscription": subId]) }
        subscribed = ids
        subId = nil
        guard !ids.isEmpty else { return }  // empty entity_ids would mean "everything"
        let id = takeId()
        subId = id
        send(["id": id, "type": "subscribe_entities", "entity_ids": Array(ids)])
    }

    // MARK: - Messaging

    private func takeId() -> Int {
        defer { nextId += 1 }
        return nextId
    }

    private func send(_ m: [String: Any]) {
        guard let ws, let d = try? JSONSerialization.data(withJSONObject: m) else { return }
        ws.send(.string(String(decoding: d, as: UTF8.self))) { _ in }
    }

    private func request(_ m: [String: Any]) async throws -> Any? {
        guard status == .connected else { throw HAError(L("Non connecté")) }
        let id = takeId()
        var m = m
        m["id"] = id
        return try await withCheckedThrowingContinuation { c in
            pending[id] = c
            send(m)
        }
    }

    private func failPending() {
        let p = pending
        pending = [:]
        p.values.forEach { $0.resume(throwing: HAError(L("Connexion perdue"))) }
    }

    // MARK: - Actions

    func call(_ domain: String, _ service: String, _ entityId: String? = nil, _ data: [String: Any] = [:]) async throws {
        var m: [String: Any] = ["type": "call_service", "domain": domain, "service": service, "service_data": data]
        if let entityId { m["target"] = ["entity_id": entityId] }
        _ = try await request(m)
    }

    func dismiss(_ n: HANotification) async {
        try? await call("persistent_notification", "dismiss", nil, ["notification_id": n.id])
    }

    func releaseNotes(_ entityId: String) async -> String? {
        try? await request(["type": "update/release_notes", "entity_id": entityId]) as? String
    }

    func loadEntities() async {
        guard let list = try? await request(["type": "get_states"]) as? [[String: Any]] else { return }
        allEntities = list.compactMap { s in
            guard let id = s["entity_id"] as? String else { return nil }
            let state = EntityState(state: s["state"] as? String ?? "", attributes: s["attributes"] as? [String: Any] ?? [:])
            return EntityRef(id: id, name: state.name ?? id, state: state)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        updateIds = Set(allEntities.map(\.id).filter { $0.hasPrefix("update.") })
        if energyDevices.isEmpty { powerIds = Set(allEntities.filter { $0.state.deviceClass == "power" && $0.state.watts != nil }.map(\.id)) }
        resubscribe()
    }

    // MARK: - Energy

    /// Entity -> area name (an entity without its own area inherits its device's), area -> floor.
    private func loadAreas() async {
        guard let areas = try? await request(["type": "config/area_registry/list"]) as? [[String: Any]],
              let devices = try? await request(["type": "config/device_registry/list"]) as? [[String: Any]],
              let entities = try? await request(["type": "config/entity_registry/list"]) as? [[String: Any]]
        else { return }
        let floors = (try? await request(["type": "config/floor_registry/list"]) as? [[String: Any]]) ?? []
        var floorName: [String: (name: String, level: Int)] = [:]
        for f in floors {
            if let id = f["floor_id"] as? String { floorName[id] = (f["name"] as? String ?? id, f["level"] as? Int ?? 0) }
        }
        var areaName: [String: String] = [:]
        var floorOf: [String: (name: String, level: Int)] = [:]
        for a in areas {
            guard let id = a["area_id"] as? String, let name = a["name"] as? String else { continue }
            areaName[id] = name
            floorOf[name] = (a["floor_id"] as? String).flatMap { floorName[$0] }
        }
        var deviceArea: [String: String] = [:]
        for d in devices { if let id = d["id"] as? String { deviceArea[id] = d["area_id"] as? String } }
        var map: [String: String] = [:]
        for e in entities {
            guard let id = e["entity_id"] as? String else { continue }
            let area = (e["area_id"] as? String) ?? (e["device_id"] as? String).flatMap { deviceArea[$0] }
            map[id] = area.flatMap { areaName[$0] }
        }
        areaByEntity = map
        floorByArea = floorOf
    }

    /// Devices from HA's Energy dashboard: the same source (and hierarchy) as its power flow card.
    private func loadEnergyPrefs() async {
        guard let prefs = try? await request(["type": "energy/get_prefs"]) as? [String: Any],
              let list = prefs["device_consumption"] as? [[String: Any]] else { return }
        energyDevices = list.compactMap { d in
            guard let stat = d["stat_consumption"] as? String, let rate = d["stat_rate"] as? String else { return nil }
            return EnergyDevice(stat: stat, rate: rate, name: d["name"] as? String, parent: d["included_in_stat"] as? String)
        }
        if !energyDevices.isEmpty { powerIds = Set(energyDevices.map(\.rate)) }
        resubscribe()
    }

    struct EnergyDevice { let stat: String; let rate: String; let name: String?; let parent: String? }
    struct PowerItem: Identifiable { let id: String; let name: String; let watts: Double }
    struct PowerArea: Identifiable { let id: String; let floor: String?; let watts: Double; let items: [PowerItem] }

    /// Live power per device grouped by area: floors top-down, rooms alphabetical (a stable order:
    /// sorting by watts made rows swap places on every update).
    /// With Energy dashboard devices, a parent only counts what its children don't, like HA's power flow.
    /// Without them, falls back to every power sensor not already shown as a tile.
    func powerByArea() -> [PowerArea] {
        let devices: [(id: String, name: String?, watts: Double)]
        if energyDevices.isEmpty {
            let shown = Set(tiles.map(\.entityId))
            devices = powerIds.subtracting(shown).compactMap { id in states[id]?.watts.map { (id, nil, $0) } }
        } else {
            devices = energyDevices.compactMap { d in
                guard let w = states[d.rate]?.watts else { return nil }
                let children = energyDevices.filter { $0.parent == d.stat }.compactMap { states[$0.rate]?.watts }.reduce(0, +)
                return (d.rate, d.name, max(w - children, 0))
            }
        }
        let items = devices.filter { $0.watts >= 1 }.map { d -> (String, PowerItem) in
            let area = areaByEntity[d.id] ?? L("Sans pièce")
            var name = d.name ?? states[d.id]?.name ?? d.id
            if name.lowercased().hasPrefix(area.lowercased() + " ") { name = String(name.dropFirst(area.count + 1)) }
            return (area, PowerItem(id: d.id, name: name, watts: d.watts))
        }
        return Dictionary(grouping: items, by: \.0)
            .map { area, list in
                PowerArea(id: area, floor: floorByArea[area]?.name, watts: list.map(\.1.watts).reduce(0, +),
                          items: list.map(\.1).sorted { $0.watts > $1.watts })
            }
            .sorted {
                let l0 = floorByArea[$0.id]?.level ?? Int.min, l1 = floorByArea[$1.id]?.level ?? Int.min
                return l0 != l1 ? l0 > l1 : $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
    }

    // MARK: - Cameras

    /// Snapshots every 2 s while open, every 60 s in background so reopening is instant. Last frame is cached on disk.
    private func startCameraLoop() {
        cameraLoop?.cancel()
        cameraLoop = Task {
            while !Task.isCancelled {
                let ids = tiles.filter { $0.kind == .camera }.map(\.entityId)
                await withTaskGroup(of: Void.self) { group in
                    for id in ids { group.addTask { await self.refreshCamera(id) } }
                }
                try? await Task.sleep(for: .seconds(isOpen ? 2 : 60))
            }
        }
    }

    private func refreshCamera(_ entityId: String) async {
        guard let base = baseURL, !token.isEmpty else { return }
        var req = URLRequest(url: base.appending(path: "api/camera_proxy/\(entityId)"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let img = NSImage(data: data) else {
                log.error("camera \(entityId, privacy: .public): HTTP \(code)")
                return
            }
            cameraImages[entityId] = img
            try? data.write(to: cacheFile(entityId))
        } catch {
            log.error("camera \(entityId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cacheFile(_ entityId: String) -> URL { cacheDir.appending(path: "\(entityId).jpg") }

    // MARK: - Tiles

    func move(_ tile: Tile, by offset: Int) {
        guard let i = tiles.firstIndex(where: { $0.id == tile.id }), tiles.indices.contains(i + offset) else { return }
        tiles.swapAt(i, i + offset)
    }

    /// Drop `section` onto `target`: it takes the target's place (after it when moving down).
    func moveSection(_ section: DashSection, to target: DashSection) {
        guard section != target, let from = sectionOrder.firstIndex(of: section),
              let to = sectionOrder.firstIndex(of: target) else { return }
        sectionOrder.remove(at: from)
        sectionOrder.insert(section, at: to)
    }

    func toggleTile(for entityId: String) {
        if tiles.contains(where: { $0.entityId == entityId }) {
            tiles.removeAll { $0.entityId == entityId }
        } else {
            tiles.append(Tile(entityId: entityId, kind: .guess(entityId)))
        }
    }

    /// Decodes tiles one by one so a tile from an older version (e.g. a removed kind) can't wipe the others.
    private static func loadTiles() -> [Tile] {
        guard let data = UserDefaults.standard.data(forKey: "tiles"),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return raw.compactMap { item in
            (try? JSONSerialization.data(withJSONObject: item)).flatMap { try? JSONDecoder().decode(Tile.self, from: $0) }
        }
    }

    private func saveTiles() {
        UserDefaults.standard.set(try? JSONEncoder().encode(tiles), forKey: "tiles")
    }
}

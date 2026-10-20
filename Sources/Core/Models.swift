import SwiftUI

enum TileKind: String, Codable, CaseIterable, Identifiable {
    case sensor, toggle, climate, camera, alarm
    var id: Self { self }

    var label: String {
        switch self {
        case .sensor: L("Capteur")
        case .toggle: L("Interrupteur")
        case .climate: L("Climat")
        case .camera: L("Caméra")
        case .alarm: L("Alarme")
        }
    }

    var plural: String {
        switch self {
        case .sensor: L("Capteurs")
        case .toggle: L("Contrôles")
        case .climate: L("Climat")
        case .camera: L("Caméras")
        case .alarm: L("Alarmes")
        }
    }

    var icon: String {
        switch self {
        case .sensor: "gauge.with.dots.needle.50percent"
        case .toggle: "switch.2"
        case .climate: "thermometer.sun.fill"
        case .camera: "video.fill"
        case .alarm: "shield.fill"
        }
    }

    static func guess(_ entityId: String) -> TileKind {
        switch entityId.split(separator: ".").first {
        case "camera": .camera
        case "alarm_control_panel": .alarm
        case "climate": .climate
        case "switch", "light", "input_boolean", "fan": .toggle
        default: .sensor
        }
    }
}

/// Dashboard sections, in the user's drag-and-drop order.
enum DashSection: String, CaseIterable, Codable {
    case sensors, energy, toggles, climate, cameras, security
}

struct Tile: Codable, Identifiable, Hashable {
    var id = UUID()
    var entityId: String
    var kind: TileKind
    var name = ""
    var icon = ""   // empty = auto
    var color = ""  // empty = auto
    var inMenuBar = false
    var armService = "alarm_arm_away"
    var inDashboard = true  // false = menu bar only (e.g. a whole-house total you don't need twice)

    init(entityId: String, kind: TileKind) {
        self.entityId = entityId
        self.kind = kind
    }

    /// Only entityId is required; kind is guessed from the domain when missing (handy in a hand-written config).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entityId = try c.decode(String.self, forKey: .entityId)
        kind = c.value(.kind, TileKind.guess(entityId))
        id = c.value(.id, UUID())
        name = c.value(.name, "")
        icon = c.value(.icon, "")
        color = c.value(.color, "")
        inMenuBar = c.value(.inMenuBar, false)
        armService = c.value(.armService, "alarm_arm_away")
        inDashboard = c.value(.inDashboard, !c.value(.hidden, false))  // "hidden" was the pre-1.1 name
    }

    private enum CodingKeys: String, CodingKey {
        case id, entityId, kind, name, icon, color, inMenuBar, armService, inDashboard, hidden
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(entityId, forKey: .entityId)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon)
        try c.encode(color, forKey: .color)
        try c.encode(inMenuBar, forKey: .inMenuBar)
        try c.encode(armService, forKey: .armService)
        try c.encode(inDashboard, forKey: .inDashboard)
    }
}

struct EntityState {
    var state: String
    var attributes: [String: Any]

    var name: String? { attributes["friendly_name"] as? String }
    var unit: String { attributes["unit_of_measurement"] as? String ?? "" }
    var deviceClass: String { attributes["device_class"] as? String ?? "" }
    var isOn: Bool { state == "on" }

    /// Power in watts, if this is a W/kW sensor.
    var watts: Double? {
        guard let v = Double(state) else { return nil }
        switch unit {
        case "W": return v
        case "kW": return v * 1000
        default: return nil
        }
    }

    static func formatWatts(_ w: Double) -> String {
        w >= 1000 ? (w / 1000).formatted(.number.precision(.fractionLength(2))) + " kW"
            : w.formatted(.number.precision(.fractionLength(0))) + " W"
    }

    var number: String? { Double(state).map { $0.formatted(.number.precision(.fractionLength(0...1))) } }

    var display: String {
        if state == "unavailable" || state == "unknown" { return "—" }
        guard let n = number else { return state.capitalized }
        return unit.isEmpty ? n : "\(n) \(unit)"
    }
}

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case auto, light, dark
    var id: Self { self }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .light: L("Clair")
        case .dark: L("Sombre")
        }
    }

    var ns: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct EntityRef: Identifiable {
    let id: String
    let name: String
    let state: EntityState
}

struct HANotification: Identifiable {
    let id: String
    let title: String
    let message: String
    let created: Date?

    init(id: String, raw: [String: Any]) {
        self.id = id
        title = raw["title"] as? String ?? "Notification"
        message = raw["message"] as? String ?? ""
        // HA sends microseconds, which ISO8601DateFormatter rejects: drop the fraction.
        let date = (raw["created_at"] as? String)?.replacing(#/\.\d+/#, with: "")
        created = date.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

// MARK: - Look

extension Tile {
    static let palette: [(name: String, color: Color)] = [
        ("orange", .orange), ("yellow", .yellow), ("green", .green), ("mint", .mint),
        ("cyan", .cyan), ("blue", .blue), ("purple", .purple), ("pink", .pink), ("red", .red),
    ]

    static let suggestedIcons = [
        "thermometer.medium", "house.fill", "bolt.fill", "sun.max.fill", "humidity.fill", "drop.fill",
        "lightbulb.fill", "power", "fan.fill", "flame.fill", "leaf.fill", "lock.fill",
        "shield.fill", "video.fill", "door.left.hand.closed", "figure.walk", "car.fill", "tv.fill",
        "washer.fill", "powerplug.fill", "wifi", "battery.75percent", "gauge.medium", "thermometer.snowflake",
    ]

    private static let sensorLook: [String: (String, Color)] = [
        "temperature": ("thermometer.medium", .orange),
        "humidity": ("humidity.fill", .cyan),
        "moisture": ("drop.fill", .cyan),
        "power": ("bolt.fill", .yellow),
        "energy": ("bolt.circle.fill", .yellow),
        "battery": ("battery.75percent", .green),
        "illuminance": ("sun.max.fill", .yellow),
        "pressure": ("gauge.medium", .purple),
        "carbon_dioxide": ("carbon.dioxide.cloud.fill", .mint),
        "door": ("door.left.hand.closed", .blue),
        "window": ("window.vertical.closed", .blue),
        "motion": ("figure.walk", .pink),
        "occupancy": ("figure.walk", .pink),
    ]

    func title(_ e: EntityState?) -> String { name.isEmpty ? (e?.name ?? entityId) : name }

    func symbol(_ e: EntityState?) -> String {
        if !icon.isEmpty { return icon }
        switch kind {
        case .camera: return "video.fill"
        case .alarm: return Alarm.symbol(e?.state)
        case .climate: return Climate.symbol(e?.state)
        case .toggle:
            if entityId.hasPrefix("light.") { return "lightbulb.fill" }
            if entityId.hasPrefix("fan.") { return "fan.fill" }
            return "power"
        case .sensor:
            return Self.sensorLook[e?.deviceClass ?? ""]?.0 ?? "gauge.with.dots.needle.50percent"
        }
    }

    /// Monochrome menu bar glyph: state must read without color (lock open/closed, outline when off).
    func menuSymbol(_ e: EntityState?) -> String {
        if kind == .alarm && icon.isEmpty { return Alarm.menuSymbol(e?.state) }
        let s = symbol(e)
        if kind == .toggle && e?.isOn != true && s.hasSuffix(".fill") { return String(s.dropLast(5)) }
        return s
    }

    func tint(_ e: EntityState?) -> Color {
        if kind == .alarm { return Alarm.color(e?.state) }
        if kind == .climate { return Climate.color(e?.state, action: e?.attributes["hvac_action"] as? String) }
        if let c = Self.palette.first(where: { $0.name == color }) { return c.color }
        if kind == .toggle { return .yellow }
        return Self.sensorLook[e?.deviceClass ?? ""]?.1 ?? .blue
    }
}

/// HA climate entities: state = hvac mode, attributes.hvac_action = what it's doing right now.
enum Climate {
    static func symbol(_ mode: String?) -> String {
        switch mode {
        case "heat": "flame.fill"
        case "cool": "snowflake"
        case "heat_cool", "auto": "arrow.triangle.2.circlepath"
        case "dry": "humidity.fill"
        case "fan_only": "fan.fill"
        default: "power"
        }
    }

    static func color(_ mode: String?, action: String?) -> Color {
        switch action ?? mode {
        case "heating", "heat": .orange
        case "cooling", "cool": .blue
        case "drying", "dry": .cyan
        case "fan", "fan_only": .teal
        case "heat_cool", "auto": .green
        default: .gray  // idle, off, unknown
        }
    }

    static func label(_ mode: String?) -> String {
        switch mode {
        case "off": L("Arrêt")
        case "heat": L("Chauffage")
        case "cool": L("Climatisation")
        case "heat_cool", "auto": "Auto"
        case "dry": L("Déshumidification")
        case "fan_only": L("Ventilation")
        default: L("Indisponible")
        }
    }

    /// What it's doing now (hvac_action), falling back to the mode.
    static func status(_ mode: String?, action: String?) -> String {
        switch action {
        case "heating": L("Chauffe")
        case "cooling": L("Refroidit")
        case "idle": L("Au repos")
        case "drying": L("Déshumidifie")
        case "fan": L("Ventile")
        default: label(mode)
        }
    }
}

enum Alarm {
    static func menuSymbol(_ s: String?) -> String {
        switch s {
        case "disarmed": "lock.open.fill"
        case "triggered": "bell.and.waves.left.and.right.fill"
        case "arming", "pending": "lock.badge.clock.fill"
        case nil, "unavailable", "unknown": "questionmark.circle"
        default: "lock.fill"
        }
    }

    static func symbol(_ s: String?) -> String {
        switch s {
        case "disarmed": "shield.slash.fill"
        case "triggered", "pending", "arming": "exclamationmark.shield.fill"
        default: "checkmark.shield.fill"
        }
    }

    static func color(_ s: String?) -> Color {
        switch s {
        case "disarmed": .green
        case "arming", "pending", "disarming": .orange
        case nil, "unavailable", "unknown": .secondary
        default: .red
        }
    }

    /// Header-sized: "Armée" instead of "Armée · absent".
    static func shortLabel(_ s: String?) -> String {
        s?.hasPrefix("armed") == true ? L("Armée") : label(s)
    }

    static func label(_ s: String?) -> String {
        switch s {
        case "disarmed": L("Désarmée")
        case "armed_away": L("Armée · absent")
        case "armed_home": L("Armée · présent")
        case "armed_night": L("Armée · nuit")
        case "armed_vacation": L("Armée · vacances")
        case "arming": L("Armement…")
        case "disarming": L("Désarmement…")
        case "pending": L("En attente…")
        case "triggered": L("Déclenchée !")
        default: L("Indisponible")
        }
    }
}

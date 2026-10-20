import Foundation
import os

private let log = Logger(subsystem: "com.mathieuletyrant.habar", category: "config")

/// Everything the user configures, in ~/.config/habar/config.json: readable, hand-editable, dotfiles-friendly.
/// Machine-specific connection settings are not in here: the URL stays in UserDefaults, the token in the Keychain.
struct Config: Codable {
    var tiles: [Tile] = []
    var sectionOrder = DashSection.allCases
    var appearance = Appearance.auto
    var language: Language?  // nil = follow the system
    var showEnergy = true
    var menuShowHouse = true
    var menuShowBadge = true
    var mirrorNotify: [String] = []  // notify.* services (e.g. "mobile_app_iphone") also shown as macOS notifications

    static let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/habar/config.json")

    init() {}

    /// Every key is optional, so a hand-written file only needs what it changes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        tiles = c.value(.tiles, [Lenient<Tile>]()).compactMap(\.value)  // one bad tile doesn't drop the rest
        let order = c.value(.sectionOrder, [Lenient<DashSection>]()).compactMap(\.value)
        sectionOrder = order + DashSection.allCases.filter { !order.contains($0) }  // sections added later go last
        appearance = c.value(.appearance, d.appearance)
        language = c.value(.language, d.language)
        showEnergy = c.value(.showEnergy, d.showEnergy)
        menuShowHouse = c.value(.menuShowHouse, d.menuShowHouse)
        menuShowBadge = c.value(.menuShowBadge, d.menuShowBadge)
        mirrorNotify = c.value(.mirrorNotify, d.mirrorNotify)
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: file) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            // never overwrite a file we couldn't read: keep it aside, start fresh
            let backup = file.appendingPathExtension("broken")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: file, to: backup)
            log.error("config.json unreadable, saved as \(backup.path, privacy: .public): \(error, privacy: .public)")
            return Config()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(self).write(to: Self.file)  // not atomic: follows a dotfiles symlink instead of replacing it
        } catch {
            log.error("config.json not saved: \(error, privacy: .public)")
        }
    }
}

/// Decodes to nil instead of failing, so one bad array element doesn't sink the whole array.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    /// Missing or invalid key -> default.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

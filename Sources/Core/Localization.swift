import Foundation
import Observation

enum Language: String, CaseIterable, Identifiable, Codable {
    case fr, en
    var id: Self { self }
    var label: String { self == .fr ? "Français" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }
}

/// Observed, so every view reading a string through L() re-renders when the language changes.
@Observable final class Lang {
    static let shared = Lang()
    static let system: Language = Locale.current.language.languageCode == .french ? .fr : .en
    var current = system {
        didSet { onChange?() }
    }
    @ObservationIgnored var onChange: (() -> Void)?  // HAClient saves the config
}

/// UI strings are written in French in code; L() swaps in English when selected (falls back to French).
func L(_ fr: String) -> String {
    Lang.shared.current == .en ? (english[fr] ?? fr) : fr
}

// build.sh warns about any L() string missing here.
private let english: [String: String] = [
    "Absent": "Away",
    "Affichage": "Display",
    "Agrandir": "Expand",
    "Ajoute des entités via ⚙︎": "Add entities in ⚙︎",
    "Ajouter": "Add",
    "Ajouter des entités": "Add entities",
    "Alarme": "Alarm",
    "Alarmes": "Alarms",
    "Allumé": "On",
    "Armée · absent": "Armed · away",
    "Armée · nuit": "Armed · night",
    "Armée · présent": "Armed · home",
    "Armée · vacances": "Armed · vacation",
    "Armement…": "Arming…",
    "Armer": "Arm",
    "Armer en": "Arm mode",
    "Aucune notification ni mise à jour": "No notifications or updates",
    "Aucune tuile": "No tiles",
    "Autres": "Other",
    "Barre de menu": "Menu bar",
    "Caméra": "Camera",
    "Caméras": "Cameras",
    "Capteur": "Sensor",
    "Capteurs": "Sensors",
    "Clair": "Light",
    "Compteur de notifications": "Notification count",
    "Connecté": "Connected",
    "Connecter": "Connect",
    "Connexion": "Connection",
    "Connexion perdue": "Connection lost",
    "Connexion…": "Connecting…",
    "Contrôles": "Controls",
    "Couleur": "Color",
    "Déclenchée !": "Triggered!",
    "Désarmée": "Disarmed",
    "Désarmement…": "Disarming…",
    "Désarmer": "Disarm",
    "Effacer": "Dismiss",
    "Envoyer": "Send",
    "En attente…": "Pending…",
    "Énergie par pièce": "Energy by room",
    "Enregistré": "Saved",
    "Entités": "Entities",
    "Erreur Home Assistant": "Home Assistant error",
    "Éteint": "Off",
    "Général": "General",
    "Glisser pour réordonner": "Drag to reorder",
    "Icône": "Icon",
    "Icône maison": "House icon",
    "Indisponible": "Unavailable",
    "Installer": "Install",
    "Interrupteur": "Switch",
    "Lancer au démarrage": "Launch at login",
    "Langue": "Language",
    "Les notifications envoyées par tes automatisations aux services cochés s'affichent aussi sur ce Mac.": "Notifications your automations send to the checked services also show up on this Mac.",
    "Les notifications fonctionnent ✓": "Notifications work ✓",
    "Maison": "Home",
    "Mises à jour": "Updates",
    "Nom": "Name",
    "Non configuré": "Not configured",
    "Non connecté": "Not connected",
    "Notes complètes": "Full release notes",
    "Notification de test": "Test notification",
    "Notifications sur le Mac": "Notifications on this Mac",
    "Nuit": "Night",
    "Pas de notes de version": "No release notes",
    "Présent": "Home",
    "Quitter": "Quit",
    "Rechercher une entité": "Search entities",
    "Réduire": "Collapse",
    "Réglages": "Settings",
    "Retirer": "Remove",
    "Sans pièce": "No room",
    "Sécurité": "Security",
    "Serveur": "Server",
    "Sombre": "Dark",
    "Tableau de bord": "Dashboard",
    "Thème": "Theme",
    "Token invalide": "Invalid token",
    "Token longue durée": "Long-lived token",
    "Total maison moins la somme des pièces": "House total minus all rooms",
    "Tous les capteurs de puissance, groupés": "All power sensors, grouped",
    "Tout": "All",
    "Tout effacer": "Clear all",
    "Tout est calme": "All quiet",
    "URL invalide": "Invalid URL",
]

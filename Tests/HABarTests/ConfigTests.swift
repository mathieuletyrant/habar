import Foundation
import Testing
@testable import HABar

@Test func handWrittenConfigFillsDefaults() throws {
    let json = """
    {
      "sectionOrder": ["cameras", "nope"],
      "tiles": [
        { "entityId": "camera.door" },
        { "kind": "sensor" },
        { "entityId": "sensor.power", "inDashboard": false }
      ]
    }
    """
    let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    #expect(c.showEnergy && c.menuShowHouse && c.language == nil)
    #expect(c.sectionOrder.first == .cameras && c.sectionOrder.count == DashSection.allCases.count)
    #expect(c.tiles.count == 2)                // the tile without entityId is dropped, not the whole list
    #expect(c.tiles[0].kind == .camera)        // guessed from the domain
    #expect(c.tiles[1].inDashboard == false)
}

@Test func slugMatchesHomeAssistant() {
    #expect(HAClient.slug("Mathieu's iPhone") == "mathieus_iphone")
    #expect(HAClient.slug("iPhone de Julie") == "iphone_de_julie")
    #expect(HAClient.slug("Salle à manger") == "salle_a_manger")
}

@Test func habarLinks() {
    #expect(HAClient.linkAction(URL(string: "habar://toggle/light.desk")!)
            == .init(domain: "homeassistant", service: "toggle", entityId: "light.desk", data: [:]))
    #expect(HAClient.linkAction(URL(string: "habar://call/light/turn_on?entity_id=light.desk&brightness=80")!)
            == .init(domain: "light", service: "turn_on", entityId: "light.desk", data: ["brightness": "80"]))
    #expect(HAClient.linkAction(URL(string: "habar://call/scene/turn_on?entity_id=scene.evening")!)?.entityId == "scene.evening")
    #expect(HAClient.linkAction(URL(string: "habar://nope")!) == nil)
    #expect(HAClient.linkAction(URL(string: "https://toggle/light.desk")!) == nil)
}

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
        { "entityId": "sensor.power", "hidden": true }
      ]
    }
    """
    let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    #expect(c.showEnergy && c.menuShowHouse && c.language == nil)
    #expect(c.sectionOrder.first == .cameras && c.sectionOrder.count == DashSection.allCases.count)
    #expect(c.tiles.count == 2)                // the tile without entityId is dropped, not the whole list
    #expect(c.tiles[0].kind == .camera)        // guessed from the domain
    #expect(c.tiles[1].inDashboard == false)   // legacy "hidden" key
}

@Test func slugMatchesHomeAssistant() {
    #expect(HAClient.slug("Mathieu's iPhone") == "mathieus_iphone")
    #expect(HAClient.slug("iPhone de Julie") == "iphone_de_julie")
    #expect(HAClient.slug("Salle à manger") == "salle_a_manger")
}

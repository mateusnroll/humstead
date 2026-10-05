import Foundation
import Testing

struct MixSettingsTests {
  @Test func stationPresetRecallAndReset() throws {
    var settings = MixSettings()
    #expect(settings.presetID == "music-only")
    settings.selectPreset("rainy-window")
    #expect(settings.mix["rain"] == AmbienceLevel(enabled: true, level: 0.35))
    settings.setLayer("rain", enabled: true, level: 0.7)
    settings.selectStation("jazzy")
    #expect(settings.presetID == "music-only")
    settings.selectPreset("forest")
    settings.selectStation("mellow")
    #expect(settings.presetID == "rainy-window")
    #expect(settings.mix["rain"]?.level == 0.7)
    settings.selectPreset("cafe")
    settings.selectPreset("rainy-window")
    #expect(settings.mix["rain"]?.level == 0.7)
    settings.musicVolume = 0
    settings.resetAmbience()
    #expect(settings.mix["rain"]?.level == 0.35)
    #expect(settings.musicVolume == 0)
    let copy = try JSONDecoder().decode(MixSettings.self, from: JSONEncoder().encode(settings))
    #expect(copy == settings)
    for preset in MixSettings.presets {
      #expect(
        Set(MixSettings.original(preset.id).keys) == Set(["rain", "cafe", "fireplace", "forest"]))
    }
  }
}

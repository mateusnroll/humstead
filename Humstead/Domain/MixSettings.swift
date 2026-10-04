import Foundation

struct AmbienceLevel: Codable, Equatable, Sendable {
  var enabled = false
  var level = 0.25
}

struct MixSettings: Codable, Equatable, Sendable {
  struct Preset: Identifiable, Sendable {
    let id: String
    let title: String
    let sound: String?
    let level: Double
  }
  struct Station: Codable, Equatable, Sendable {
    var selectedPresetID = "music-only"
    var presetMixes: [String: [String: AmbienceLevel]] = [:]
  }
  static let stationIDs = ["mellow", "jazzy", "late-night"]
  static let soundIDs = ["rain", "cafe", "fireplace", "forest"]
  static let presets: [Preset] = [
    Preset(id: "music-only", title: "Music Only", sound: nil, level: 0),
    Preset(id: "rainy-window", title: "Rainy Window", sound: "rain", level: 0.35),
    Preset(id: "cafe", title: "Café", sound: "cafe", level: 0.25),
    Preset(id: "fireside", title: "Fireside", sound: "fireplace", level: 0.30),
    Preset(id: "forest", title: "Forest", sound: "forest", level: 0.30),
  ]
  var schemaVersion = 1
  var currentStationID = "mellow"
  var musicVolume = 0.65
  var stationSettings: [String: Station] = [:]
  var analyticsChoice = "undecided"

  var presetID: String { stationSettings[currentStationID]?.selectedPresetID ?? "music-only" }
  var presetTitle: String { Self.presets.first { $0.id == presetID }?.title ?? "Music Only" }
  var mix: [String: AmbienceLevel] {
    stationSettings[currentStationID]?.presetMixes[presetID] ?? Self.original(presetID)
  }
  static func original(_ id: String) -> [String: AmbienceLevel] {
    let preset = presets.first { $0.id == id }
    return Dictionary(
      uniqueKeysWithValues: soundIDs.map { sound in
        (
          sound,
          AmbienceLevel(
            enabled: sound == preset?.sound, level: sound == preset?.sound ? preset!.level : 0.25)
        )
      })
  }
  mutating func selectStation(_ id: String) {
    guard Self.stationIDs.contains(id) else { return }
    currentStationID = id
  }
  mutating func selectPreset(_ id: String) {
    guard Self.presets.contains(where: { $0.id == id }) else { return }
    stationSettings[currentStationID, default: Station()].selectedPresetID = id
  }
  mutating func setLayer(_ id: String, enabled: Bool, level: Double) {
    guard Self.soundIDs.contains(id), level.isFinite, (0...1).contains(level) else { return }
    var updated = mix
    updated[id] = AmbienceLevel(enabled: enabled, level: level)
    stationSettings[currentStationID, default: Station()].presetMixes[presetID] = updated
  }
  mutating func resetAmbience() {
    stationSettings[currentStationID, default: Station()].presetMixes[presetID] = Self.original(
      presetID)
  }
  func validated() throws -> MixSettings {
    guard schemaVersion == 1, musicVolume.isFinite, (0...1).contains(musicVolume),
      ["undecided", "enabled", "disabled"].contains(analyticsChoice)
    else { throw SettingsError.invalid }
    var result = self
    if !Self.stationIDs.contains(currentStationID) { result.currentStationID = "mellow" }
    result.stationSettings = [:]
    for (id, var station) in stationSettings where Self.stationIDs.contains(id) {
      if !Self.presets.contains(where: { $0.id == station.selectedPresetID }) {
        station.selectedPresetID = "music-only"
      }
      var mixes: [String: [String: AmbienceLevel]] = [:]
      for (preset, layers) in station.presetMixes
      where Self.presets.contains(where: { $0.id == preset }) {
        var known = Self.original(preset)
        for (sound, value) in layers {
          guard value.level.isFinite, (0...1).contains(value.level) else {
            throw SettingsError.invalid
          }
          if Self.soundIDs.contains(sound) { known[sound] = value }
        }
        mixes[preset] = known
      }
      station.presetMixes = mixes
      result.stationSettings[id] = station
    }
    return result
  }
}

enum SettingsError: Error { case invalid }

import AppKit
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: PlayerModel
  @FocusState private var focusedControl: Control?

  private enum Control: Hashable {
    case station, creator, original, credits, playback, next, volume, preset, reset, timer,
      cancelTimer
    case layerToggle(String)
    case layerVolume(String)
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack {
            Text("Humstead").font(.headline).accessibilityIdentifier("humstead-heading")
            Spacer()
            Image(systemName: "waveform").foregroundStyle(.secondary).accessibilityHidden(true)
          }
          Picker(
            "Station", selection: Binding(get: { model.state.stationID }, set: model.selectStation)
          ) {
            ForEach(model.state.catalog?.stations ?? []) { station in
              Text(station.title).tag(station.id)
            }
          }
          .pickerStyle(.menu)
          .focused($focusedControl, equals: .station)
          .id(Control.station)
          .accessibilityLabel("Station")
          .disabled(model.state.catalog == nil)

          VStack(alignment: .leading, spacing: 10) {
            Text(model.track?.title ?? "A quiet moment")
              .font(.system(size: 28, weight: .semibold, design: .rounded))
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("track-title")
            if let track = model.track {
              Link(destination: track.profileURL ?? track.sourceURL) {
                Text(track.creator).font(.title3)
              }
              .accessibilityLabel("Creator: \(track.creator)")
              .focused($focusedControl, equals: .creator)
              .id(Control.creator)
              HStack(spacing: 14) {
                Link("Original recording", destination: track.sourceURL)
                  .focused($focusedControl, equals: .original)
                  .id(Control.original)
                CreditsButton(model: model)
                  .focused($focusedControl, equals: .credits)
                  .id(Control.credits)
              }
              .font(.callout)
            }
          }
          .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)

          HStack(spacing: 16) {
            Button(action: model.togglePlayback) {
              Label(
                model.state.playbackRequested ? "Pause" : "Play",
                systemImage: model.state.playbackRequested ? "pause.fill" : "play.fill"
              )
              .frame(minWidth: 100, minHeight: 30)
            }
            .focused($focusedControl, equals: .playback)
            .id(Control.playback)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.state.catalog == nil)
            Button(action: model.next) {
              Image(systemName: "forward.end.fill").frame(width: 28, height: 30)
            }
            .focused($focusedControl, equals: .next)
            .id(Control.next)
            .accessibilityLabel("Next track")
            .help("Next track")
            .disabled(!model.canNext)
            Spacer()
          }
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Music volume")
              Spacer()
              Text(model.state.volume, format: .percent.precision(.fractionLength(0)))
                .foregroundStyle(.secondary).monospacedDigit().accessibilityHidden(true)
            }
            Slider(
              value: Binding(get: { Double(model.state.volume) }, set: model.setVolume), in: 0...1,
              step: 0.01
            ) {
              Text("Music volume")
            }
            .focused($focusedControl, equals: .volume)
            .id(Control.volume)
            .labelsHidden()
            .accessibilityLabel("Music volume")
            .accessibilityIdentifier("music-volume")
            .disabled(model.state.catalog == nil)
            .accessibilityValue("\(Int(model.state.volume * 100)) percent")
          }
          Group {
            Picker(
              "Ambience preset",
              selection: Binding(get: { model.settings.presetID }, set: model.selectPreset)
            ) {
              ForEach(MixSettings.presets) { preset in Text(preset.title).tag(preset.id) }
            }
            .focused($focusedControl, equals: .preset)
            .id(Control.preset)
            .accessibilityLabel("Ambience preset")
            Button("Reset ambience", action: model.resetAmbience)
              .focused($focusedControl, equals: .reset)
              .id(Control.reset)
            LazyVStack(alignment: .leading, spacing: 24) {
              ForEach(model.sounds) { sound in
                let id = sound.id
                let title =
                  ["rain": "Rain", "cafe": "Café", "fireplace": "Fireplace", "forest": "Forest"][id]
                  ?? sound.title
                let level = model.settings.mix[id] ?? AmbienceLevel()
                VStack(alignment: .leading, spacing: 6) {
                  Toggle(
                    title,
                    isOn: Binding(get: { level.enabled }, set: { model.setLayer(id, enabled: $0) })
                  )
                  .toggleStyle(.checkbox)
                  .accessibilityIdentifier("ambience-toggle-\(id)")
                  .focused($focusedControl, equals: .layerToggle(id))
                  .id(Control.layerToggle(id))
                  Slider(
                    value: Binding(get: { level.level }, set: { model.setLayer(id, level: $0) }),
                    in: 0...1, step: 0.01,
                    onEditingChanged: { editing in
                      if !editing { focusedControl = .layerVolume(id) }
                    }
                  ) {
                    Text("\(title) volume")
                  }
                  .labelsHidden()
                  .accessibilityLabel("\(title) volume")
                  .accessibilityIdentifier("ambience-volume-\(id)")
                  .accessibilityValue("\(Int((level.level * 100).rounded())) percent")
                  .focused($focusedControl, equals: .layerVolume(id))
                  .id(Control.layerVolume(id))
                  if let error = model.state.layerErrors[id] {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                  }
                }
                .id(id)
              }
            }
            Picker(
              "Sleep timer",
              selection: Binding(get: { model.sleepTimer.minutes }, set: model.startTimer)
            ) {
              Text("Off").tag(0)
              ForEach([15, 30, 60], id: \.self) { minutes in Text("\(minutes) minutes").tag(minutes)
              }
            }
            .accessibilityLabel("Sleep timer")
            .focused($focusedControl, equals: .timer)
            .id(Control.timer)
            if model.sleepTimer.deadline != nil {
              HStack {
                Text(
                  model.sleepTimer.isFading
                    ? "Fading out…"
                    : "\(model.countdown / 60):\(String(format: "%02d", model.countdown % 60)) remaining"
                )
                .monospacedDigit().font(.caption)
                Spacer()
                Button("Cancel timer") {
                  focusedControl = .timer
                  model.cancelTimer()
                }
                .focused($focusedControl, equals: .cancelTimer)
                .id(Control.cancelTimer)
              }
            }
          }
          .disabled(model.state.catalog == nil)
          if let warning = model.libraryState.warning {
            Text(warning).font(.callout).foregroundStyle(.secondary)
          }
          if let warning = model.persistenceWarning {
            Text(warning).font(.callout).foregroundStyle(.secondary)
              .accessibilityIdentifier("persistence-warning")
          }
          if let error = model.state.error {
            Text(error).font(.callout).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("playback-error")
          }
          Text(
            model.state.volume == 0
              ? "Music is muted"
              : model.state.isPlaying ? "Playing from your Mac" : "Ready when you are"
          )
          .font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier("playback-status")
        }
        .padding(24)
      }
      .onChange(of: focusedControl) { control in
        switch control {
        case .layerToggle(let id), .layerVolume(let id):
          proxy.scrollTo(id, anchor: .center)
        case .some(let control): proxy.scrollTo(control)
        case .none: break
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let message = model.layerMessage {
        Text(message).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
          .background(Color(nsColor: .windowBackgroundColor))
          .accessibilityIdentifier("ambience-message")
      }
    }
    .frame(minWidth: 320, minHeight: 400)
    .background(Color(nsColor: .windowBackgroundColor))
    .background(
      PlayerSpaceShortcut(isControlFocused: focusedControl != nil, action: model.togglePlayback)
        .frame(width: 0, height: 0)
    )
    .tint(Color(nsColor: .systemOrange))
  }
}

@MainActor
func openCredits() {
  if #available(macOS 14, *) {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  } else {
    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
  }
}

private struct PlayerSpaceShortcut: NSViewRepresentable {
  let isControlFocused: Bool
  let action: () -> Void
  func makeNSView(context: Context) -> SpaceShortcutView { SpaceShortcutView(action: action) }
  func updateNSView(_ view: SpaceShortcutView, context: Context) {
    view.action = action
    view.isControlFocused = isControlFocused
  }
}

private final class SpaceShortcutView: NSView {
  var action: () -> Void
  var isControlFocused = false
  private var monitor: Any?

  init(action: @escaping () -> Void) {
    self.action = action
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { nil }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    super.viewWillMove(toWindow: newWindow)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = self.window, window.isKeyWindow, event.window === window,
        event.keyCode == 49, !event.isARepeat, !self.isControlFocused,
        event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
        !(window.firstResponder is NSControl), !(window.firstResponder is NSText)
      else { return event }
      self.action()
      return nil
    }
  }
}

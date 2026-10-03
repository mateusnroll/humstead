import AppKit
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: PlayerModel
  @FocusState private var focusedControl: Control?

  private enum Control: Hashable {
    case station, creator, original, credits, playback, next, volume
  }

  var body: some View {
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
            HStack(spacing: 14) {
              Link("Original recording", destination: track.sourceURL)
                .focused($focusedControl, equals: .original)
              if #available(macOS 14, *) {
                SettingsLink { Text("Credits") }.buttonStyle(.link)
                  .focused($focusedControl, equals: .credits)
              } else {
                Button("Credits", action: openCredits).buttonStyle(.link)
                  .focused($focusedControl, equals: .credits)
              }
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
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(model.state.catalog == nil)
          Button(action: model.next) {
            Image(systemName: "forward.end.fill").frame(width: 28, height: 30)
          }
          .focused($focusedControl, equals: .next)
          .accessibilityLabel("Next track")
          .help("Next track")
          .disabled(model.state.catalog == nil)
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
          .labelsHidden()
          .accessibilityLabel("Music volume")
          .accessibilityIdentifier("music-volume")
          .accessibilityValue("\(Int(model.state.volume * 100)) percent")
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

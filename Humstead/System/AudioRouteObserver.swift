import AppKit
import CoreAudio

@MainActor
final class AudioRouteObserver {
  enum Event: Sendable { case routeChanged, sleep, wake }
  private let action: (Event) -> Void
  private var active = true
  private var listeners:
    [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
  private var notifications: [NSObjectProtocol] = []
  private var device: AudioDeviceID = 0

  init(action: @escaping (Event) -> Void) {
    self.action = action
    let center = NSWorkspace.shared.notificationCenter
    for (name, event) in [
      (NSWorkspace.willSleepNotification, Event.sleep), (NSWorkspace.didWakeNotification, .wake),
    ] {
      notifications.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor [weak self] in self?.receive(event) }
        })
    }
    observe(
      AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice)
    observeDevice()
  }
  func receive(_ event: Event) {
    guard active else { return }
    action(event)
    if event == .routeChanged { observeDevice() }
  }
  private func observe(_ object: AudioObjectID, selector: AudioObjectPropertySelector) {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: selector == kAudioDevicePropertyDataSource
        ? kAudioDevicePropertyScopeOutput : kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectHasProperty(object, &address) else { return }
    let callback: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      Task { @MainActor [weak self] in self?.receive(.routeChanged) }
    }
    if AudioObjectAddPropertyListenerBlock(object, &address, .main, callback) == noErr {
      listeners.append((object, address, callback))
    }
  }
  private func observeDevice() {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var current: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &current) == noErr,
      current != device
    else { return }
    for (object, var property, callback) in listeners where object == device {
      AudioObjectRemovePropertyListenerBlock(object, &property, .main, callback)
    }
    listeners.removeAll { $0.0 == device }
    device = current
    guard current != 0 else { return }
    for selector in [
      kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyTransportType,
      kAudioDevicePropertyDataSource,
    ] {
      observe(current, selector: selector)
    }
  }
  func stop() {
    active = false
    for (object, var property, callback) in listeners {
      AudioObjectRemovePropertyListenerBlock(object, &property, .main, callback)
    }
    listeners.removeAll()
    for notification in notifications {
      NSWorkspace.shared.notificationCenter.removeObserver(notification)
    }
    notifications.removeAll()
  }
}

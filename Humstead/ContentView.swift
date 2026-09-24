import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Humstead")
        .font(.largeTitle.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("humstead-heading")
      Text("A quiet place for music and ambience. Player in development.")
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(32)
    .frame(minWidth: 320, minHeight: 240, alignment: .leading)
  }
}

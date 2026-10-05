import SwiftUI

struct DownloadsView: View {
  @ObservedObject var model: PlayerModel
  @State private var confirmation: Confirmation?
  @State private var origin: String?
  @FocusState private var focused: String?

  private enum Confirmation: Identifiable {
    case download(DownloadPlan)
    case remove(DownloadCatalog.Collection)
    var id: String {
      switch self {
      case .download(let plan): return plan.record.collection.id
      case .remove(let collection): return collection.id
      }
    }
  }
  private func size(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          HStack {
            Text("Downloads").font(.largeTitle)
            Spacer()
            Button("Check for updates", action: model.checkForUpdates)
              .focused($focused, equals: "updates")
              .id("updates")
              .disabled(model.downloads.refreshing)
          }
          Text("Add music and ambience to your Mac for offline listening.").foregroundStyle(
            .secondary)
          if let message = model.downloads.message, message != model.downloadError {
            Text(message).font(.callout)
          }
          if let message = model.downloadError {
            Text(message).font(.callout).accessibilityIdentifier("download-message")
          }
          if let message = model.libraryState.warning { Text(message).font(.callout) }
          if model.downloadBusy {
            Text("Finish or cancel the current operation before changing another collection.").font(
              .caption)
          }
          ForEach(model.downloadCollections) { collection in
            let installed = model.libraryState.records.first { $0.collection.id == collection.id }
            let update = installed.map { $0.collection.version < collection.version } ?? false
            let ownsOperation = model.downloadingCollectionID == collection.id
            let remote =
              model.downloads.catalog?.collections.contains { $0.id == collection.id } == true
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text(collection.label).font(.headline)
                Spacer()
                Text("Version \(collection.version) · \(size(collection.totalBytes))")
                  .foregroundStyle(.secondary)
              }
              if let installed {
                Text(
                  "Installed version \(installed.collection.version)\(update ? " · Update available" : "")"
                ).font(.caption)
              }
              if model.downloads.activeID == collection.id {
                ProgressView(
                  value: Double(model.downloads.progress),
                  total: Double(max(1, model.downloads.total))
                )
                .accessibilityLabel("Downloading \(collection.label)")
                Text("\(size(model.downloads.progress)) of \(size(model.downloads.total))").font(
                  .caption)
              }
              HStack {
                Button(
                  ownsOperation
                    ? "Cancel download"
                    : model.failedDownloadID == collection.id
                      ? "Retry \(collection.label)"
                      : update
                        ? "Update \(collection.label)"
                        : installed == nil ? "Download \(collection.label)" : "Download again"
                ) {
                  if ownsOperation {
                    model.cancelDownload()
                    return
                  }
                  origin = "download-" + collection.id
                  Task {
                    if let plan = await model.downloadPlan(collection.id) {
                      confirmation = .download(plan)
                    }
                  }
                }
                .focused($focused, equals: "download-" + collection.id)
                .disabled(
                  !ownsOperation && (model.downloadBusy || !remote || model.libraryState.readOnly))
                if installed != nil {
                  Button("Remove \(collection.label)") {
                    origin = "remove-" + collection.id
                    confirmation = .remove(collection)
                  }
                  .focused($focused, equals: "remove-" + collection.id)
                  .disabled(model.downloadBusy || model.libraryState.readOnly)
                }
              }
            }
            .id(collection.id)
            Divider()
          }
        }.padding(24)
      }
      .onChange(of: focused) { control in
        if control == "updates" {
          proxy.scrollTo("updates", anchor: .top)
        } else if let collection = model.downloadCollections.first(where: {
          control == "download-" + $0.id || control == "remove-" + $0.id
        }) {
          proxy.scrollTo(collection.id, anchor: .center)
        }
      }
    }
    .onChange(of: model.removing) { removing in
      if !removing, let origin, origin.hasPrefix("remove-") {
        let id = String(origin.dropFirst(7))
        focused =
          model.libraryState.records.contains { $0.collection.id == id }
          ? origin : "download-" + id
      }
    }
    .sheet(
      item: $confirmation, onDismiss: { focused = origin },
      content: { item in
        VStack(alignment: .leading, spacing: 16) {
          switch item {
          case .download(let plan):
            Text("Download \(plan.record.collection.label)?").font(.title2)
            Text(
              "Version \(plan.record.collection.version) · \(size(plan.record.collection.totalBytes)) total"
            )
            Text(
              "\(size(plan.missingBytes)) to download. Already verified files are reused. Your installed version stays available until this download finishes."
            )
            HStack {
              Button("Cancel") { confirmation = nil }.keyboardShortcut(.cancelAction)
              Spacer()
              Button("Confirm download") {
                confirmation = nil
                model.install(plan)
              }.keyboardShortcut(.defaultAction)
            }
          case .remove(let collection):
            Text("Remove \(collection.label)?").font(.title2)
            Text(
              "If its music is playing, Humstead will switch to bundled music in this station. Removed ambience will stop and be disabled in your saved mixes; other sounds will continue. Your saved levels are kept. Shared and bundled files are kept."
            )
            HStack {
              Button("Cancel") { confirmation = nil }.keyboardShortcut(.cancelAction)
              Spacer()
              Button("Confirm removal", role: .destructive) {
                confirmation = nil
                model.removeCollection(collection.id)
              }
            }
          }
        }.padding(24).frame(width: 440)
      })
  }
}

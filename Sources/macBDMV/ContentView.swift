import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.mkvmerge == nil {
                ContentUnavailableView("MKVToolNix Not Found", systemImage: "exclamationmark.triangle",
                                       description: Text("Install it with `brew install mkvtoolnix`, then relaunch."))
            } else if model.scanning {
                ProgressView("Scanning playlists…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.titles.isEmpty {
                ContentUnavailableView {
                    Label("Open a Blu-ray Folder", systemImage: "opticaldisc")
                } description: {
                    Text("Drop a folder containing BDMV here — or a folder holding several discs.")
                } actions: {
                    Button("Open…") { openPanel(model) }
                }
            } else {
                DiscView()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !model.running else { return false }
            Task { await model.open(url) }
            return true
        }
        .alert(model.alert ?? "", isPresented: Binding(get: { model.alert != nil }, set: { _ in model.alert = nil })) {}
    }
}

private struct DiscView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack {
                TextField("Movie name", text: $model.movieName)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                Toggle("Show short clips", isOn: $model.showShortClips)
                    .toggleStyle(.checkbox)
            }
            .padding()
            .disabled(model.running)

            ForEach(model.encryptedDiscs, id: \.root) { disc in
                Banner(text: "\(disc.label.isEmpty ? "This disc" : disc.label) is still AACS-encrypted. Make a decrypted backup with MakeMKV first.",
                       systemImage: "lock.fill", color: .red)
            }
            if model.looksObfuscated {
                Banner(text: "Several playlists share the feature's length — this disc may use playlist obfuscation. Check runtime and chapters before remuxing.",
                       systemImage: "exclamationmark.triangle.fill", color: .orange)
            }

            VSplitView {
                TitleTable().frame(minHeight: 160)
                TrackTable().frame(minHeight: 120)
            }
            .disabled(model.running)

            Divider()
            Footer().padding(12)
        }
    }
}

private struct Banner: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, 8)
    }
}

private struct TitleTable: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(of: Title.self, selection: $model.selection) {
            TableColumn("") { t in
                Toggle("", isOn: model.binding(t, \.selected)).labelsHidden()
            }
            .width(20)
            TableColumn("Playlist") { t in
                Text([t.disc, t.playlist].filter { !$0.isEmpty }.joined(separator: " · "))
                    .help(t.duplicates.isEmpty ? "" : "Same content as \(t.duplicates.joined(separator: ", "))")
            }
            .width(min: 60, ideal: 90)
            TableColumn("Length") { t in
                Text(Duration.seconds(t.duration).formatted(.time(pattern: .hourMinuteSecond))).monospacedDigit()
            }
            .width(64)
            TableColumn("Size") { t in Text(t.size.formatted(.byteCount(style: .file))) }
                .width(70)
            TableColumn("Chapters") { t in Text("\(t.chapters)").monospacedDigit() }
                .width(56)
            TableColumn("Type") { t in
                Picker("", selection: model.binding(t, \.kind)) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            .width(min: 110, ideal: 140)
            TableColumn("Name") { t in
                TextField("", text: model.binding(t, \.name))
                    .disabled(t.kind == .main && t.selected)
                    .help(t.kind == .main ? "Main features are named after the movie" : "")
            }
            TableColumn("") { t in StatusView(state: t.state) }
                .width(90)
        } rows: {
            ForEach(model.visibleTitles) { TableRow($0) }
        }
    }
}

private struct TrackTable: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let title = model.titles.first(where: { $0.id == model.selection }) {
            Table(of: Track.self) {
                TableColumn("") { tr in
                    let i = title.tracks.firstIndex { $0.id == tr.id }!
                    Toggle("", isOn: model.binding(title, \.tracks[i].keep)).labelsHidden()
                }
                .width(20)
                TableColumn("ID") { tr in Text("\(tr.id)").monospacedDigit() }.width(28)
                TableColumn("Type") { tr in Text(tr.type.capitalized) }.width(80)
                TableColumn("Codec") { tr in Text(Track.shortCodec(tr.codec)) }
                TableColumn("Language") { tr in Text(Language.name(tr.language)) }
                TableColumn("Details") { tr in Text(tr.detail) }
            } rows: {
                ForEach(title.tracks) { TableRow($0) }
            }
        } else {
            Text("Select a title to choose its tracks.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StatusView: View {
    let state: JobState

    var body: some View {
        switch state {
        case .idle: EmptyView()
        case .queued: Text("Queued").foregroundStyle(.secondary)
        case .running(let p): ProgressView(value: p)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning(let m): Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).help(m)
        case .failed(let m): Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).help(m)
        }
    }
}

private struct Footer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let free = model.freeBytes
        let short = free.map { model.requiredBytes >= $0 } ?? false
        HStack {
            Button {
                if let url = chooseFolder(prompt: "Choose") { model.outputDir = url }
            } label: {
                Label(model.outputDir.lastPathComponent, systemImage: "folder")
            }
            .help(model.outputDir.path(percentEncoded: false))
            .disabled(model.running)
            Text("\(model.requiredBytes.formatted(.byteCount(style: .file))) needed · \((free ?? 0).formatted(.byteCount(style: .file))) free")
                .foregroundStyle(short ? .red : .secondary)
            Spacer()
            if model.running {
                ProgressView(value: model.progress).frame(width: 160)
                Button("Cancel") { model.cancel() }
            } else {
                if FileManager.default.fileExists(atPath: model.movieFolder.path) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.movieFolder]) }
                }
                Button("Remux \(model.queue.count) Title\(model.queue.count == 1 ? "" : "s")") {
                    Task { await model.start() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStart)
            }
        }
    }
}

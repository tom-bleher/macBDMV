import AppKit
import SwiftUI

@MainActor @Observable
final class AppModel {
    static let shortClip: TimeInterval = 120

    let mkvmerge = Remuxer.locate()
    var discs: [Disc] = []
    var titles: [Title] = [] { didSet { nameMainFeatures() } }
    var movieName = "" { didSet { nameMainFeatures() } }
    var selection: Title.ID?
    var showShortClips = false
    var scanning = false
    var running = false
    var alert: String?
    var outputDir = URL(filePath: UserDefaults.standard.string(forKey: "outputDir")
                        ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].path) {
        didSet { UserDefaults.standard.set(outputDir.path, forKey: "outputDir") }
    }

    private var process: Process?
    private var cancelled = false

    var visibleTitles: [Title] { showShortClips ? titles : titles.filter { $0.duration >= Self.shortClip || $0.selected } }
    var queue: [Title] { titles.filter(\.selected) }
    var requiredBytes: Int64 { queue.reduce(0) { $0 + $1.size } }
    var movieFolder: URL { outputDir.appending(path: safe(movieName), directoryHint: .isDirectory) }

    var freeBytes: Int64? {
        let v = try? outputDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? v?.volumeAvailableCapacity.map(Int64.init)
    }

    /// Size-weighted progress over the queue.
    var progress: Double {
        let total = Double(max(requiredBytes, 1))
        return queue.reduce(0) { sum, t in
            switch t.state {
            case .running(let p): sum + p * Double(t.size) / total
            case .done, .warning, .failed: sum + Double(t.size) / total
            default: sum
            }
        }
    }

    var encryptedDiscs: [Disc] { discs.filter(\.encrypted) }

    /// Obfuscated discs carry many playlists of the main feature's length with shuffled clips.
    var looksObfuscated: Bool {
        let longest = titles.map(\.duration).max() ?? 0
        return titles.filter { $0.duration > longest * 0.98 }.count >= 4
    }

    var canStart: Bool {
        !running && !scanning && !queue.isEmpty && encryptedDiscs.isEmpty && !movieName.isEmpty
            && requiredBytes < (freeBytes ?? .max)
    }

    func open(_ url: URL) async {
        guard let mkvmerge, !running else { return }
        let roots = Scanner.discRoots(in: url)
        guard !roots.isEmpty else {
            alert = "No BDMV folder found in “\(url.lastPathComponent)”."
            return
        }
        scanning = true
        discs = []
        titles = []
        selection = nil
        movieName = Scanner.movieName(for: url)

        var found: [Title] = []
        for root in roots {
            let label = roots.count > 1 ? root.lastPathComponent : ""
            let (disc, discTitles) = await Scanner.scan(root: root, label: label, mkvmerge: mkvmerge)
            discs.append(disc)
            found += discTitles
        }

        // Everything at least half as long as the longest title is treated as (a part of) the feature.
        let longest = found.map(\.duration).max() ?? 0
        for i in found.indices {
            let isMain = found[i].duration >= longest / 2
            found[i].kind = isMain ? .main : .other
            found[i].selected = isMain
            if !isMain { found[i].name = [found[i].disc, found[i].playlist].filter { !$0.isEmpty }.joined(separator: " ") }
        }
        func order(_ t: Title) -> (String, Int, String) { (t.disc, t.kind == .main ? 0 : 1, t.playlist) }
        titles = found.sorted { order($0) < order($1) }
        selection = titles.first?.id
        scanning = false
        if titles.isEmpty { alert = "No playable titles found." }
    }

    func start() async {
        guard let mkvmerge, canStart else { return }
        running = true
        cancelled = false
        let ids = queue.map(\.id)
        for id in ids { update(id) { $0.state = .queued } }

        for id in ids {
            guard !cancelled, let title = titles.first(where: { $0.id == id }) else {
                update(id) { $0.state = .idle }
                continue
            }
            let dest = outputURL(for: title)
            if FileManager.default.fileExists(atPath: dest.path) {
                update(id) { $0.state = .failed("\(dest.lastPathComponent) already exists.") }
                continue
            }
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let part = dest.appendingPathExtension("part")
            update(id) { $0.state = .running(0) }

            let (status, messages) = await run(mkvmerge, Remuxer.arguments(for: title, output: part)) { p in
                self.update(id) { $0.state = .running(p) }
            }
            // mkvmerge: 0 = success, 1 = success with warnings, 2 = error.
            if status <= 1 && !cancelled, (try? FileManager.default.moveItem(at: part, to: dest)) != nil {
                update(id) { $0.state = status == 0 ? .done : .warning(messages.joined(separator: "\n")) }
            } else {
                try? FileManager.default.removeItem(at: part)
                update(id) { $0.state = self.cancelled ? .idle : .failed(messages.last ?? "mkvmerge exited with status \(status).") }
            }
        }
        running = false
    }

    func cancel() {
        cancelled = true
        process?.terminate()
    }

    func outputURL(for title: Title) -> URL {
        var url = movieFolder
        if title.kind != .main { url.append(path: title.kind.rawValue, directoryHint: .isDirectory) }
        return url.appending(path: safe(title.name) + ".mkv")
    }

    func binding<V>(_ title: Title, _ path: WritableKeyPath<Title, V>) -> Binding<V> {
        Binding(
            get: { self.titles.first { $0.id == title.id }?[keyPath: path] ?? title[keyPath: path] },
            set: { value in self.update(title.id) { $0[keyPath: path] = value } }
        )
    }

    private func update(_ id: Title.ID, _ change: (inout Title) -> Void) {
        if let i = titles.firstIndex(where: { $0.id == id }) { change(&titles[i]) }
    }

    /// Selected main titles are named after the movie, with Plex-style "- ptN" suffixes when there are several.
    private func nameMainFeatures() {
        let mains = titles.indices.filter { titles[$0].kind == .main && titles[$0].selected }
        for (n, i) in mains.enumerated() {
            let name = mains.count == 1 ? movieName : "\(movieName) - pt\(n + 1)"
            if titles[i].name != name { titles[i].name = name }
        }
    }

    private func safe(_ name: String) -> String {
        name.replacing(/[\/:]/, with: "-").trimmingCharacters(in: .whitespaces)
    }

    private func run(_ exe: URL, _ args: [String], progress: (Double) -> Void) async -> (Int32, [String]) {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (2, [error.localizedDescription]) }
        process = p
        defer { process = nil }

        var messages: [String] = []
        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                if line.hasPrefix("#GUI#progress "), let pct = Double(line.dropFirst(14).dropLast()) {
                    progress(pct / 100)
                } else if line.hasPrefix("#GUI#warning ") || line.hasPrefix("#GUI#error ") {
                    messages.append(String(line.drop { $0 != " " }.dropFirst()))
                }
            }
        } catch {}
        p.waitUntilExit()  // stdout hit EOF, so mkvmerge is exiting
        return (p.terminationStatus, messages)
    }
}

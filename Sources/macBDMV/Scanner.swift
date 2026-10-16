import Foundation

struct Disc {
    let root: URL  // folder containing BDMV/
    let label: String
    let encrypted: Bool
}

enum Scanner {
    /// Folders at or up to two levels below `url` that contain BDMV/PLAYLIST.
    static func discRoots(in url: URL) -> [URL] {
        let fm = FileManager.default
        func isRoot(_ u: URL) -> Bool {
            var dir: ObjCBool = false
            return fm.fileExists(atPath: u.appending(path: "BDMV/PLAYLIST").path, isDirectory: &dir) && dir.boolValue
        }
        func children(_ u: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey],
                                          options: .skipsHiddenFiles)) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        if url.lastPathComponent == "BDMV" { return [url.deletingLastPathComponent()] }
        if isRoot(url) { return [url] }
        var roots: [URL] = []
        for child in children(url) {
            if isRoot(child) { roots.append(child) } else { roots += children(child).filter(isRoot) }
        }
        return roots
    }

    /// Guesses "Title (Year)" from folder names like "Parasite.2019.UHD.BluRay-GRP" or "DISC01" inside "Parasite (2019)".
    static func movieName(for url: URL) -> String {
        var url = url
        if url.lastPathComponent == "BDMV" { url.deleteLastPathComponent() }
        let generic = /^(?i)(disc|disk|bd|bdmv|d)[\s._-]*\d*$/
        while url.lastPathComponent.wholeMatch(of: generic) != nil, url.pathComponents.count > 2 {
            url.deleteLastPathComponent()
        }
        let raw = url.lastPathComponent
        if let m = raw.firstMatch(of: /^(.+?)[\s._(\[]+((?:19|20)\d{2})(?:[\s._)\]]|$)/) {
            return "\(clean(String(m.1))) (\(m.2))"
        }
        return clean(raw)
    }

    private static func clean(_ s: String) -> String {
        s.replacing(/[._]+/, with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// An AACS-encrypted m2ts has scrambled TS sync bytes after the first 16 bytes of every 6144-byte aligned unit.
    static func isEncrypted(_ m2ts: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: m2ts) else { return false }
        defer { try? fh.close() }
        let unit = 6144
        for offset in [0, unit * 100, unit * 1000] {
            guard (try? fh.seek(toOffset: UInt64(offset))) != nil,
                  let data = try? fh.read(upToCount: unit), data.count == unit else { break }
            if (0..<32).contains(where: { data[data.startIndex + $0 * 192 + 4] != 0x47 }) { return true }
        }
        return false
    }

    /// The longest title is the feature. Other titles at least half as long are further parts (multi-part
    /// films, one per disc) only if they share no clips with it; otherwise they are alternate cuts.
    static func markFeatures(_ titles: inout [Title]) {
        let longest = titles.map(\.duration).max() ?? 0
        var featureClips = Set<String>()
        for i in titles.indices.sorted(by: { titles[$0].duration > titles[$1].duration }) {
            let clips = Set(titles[i].clips)
            let isMain = titles[i].duration >= longest / 2 && featureClips.isDisjoint(with: clips)
            if isMain { featureClips.formUnion(clips) }
            titles[i].kind = isMain ? .main : .other
            titles[i].selected = isMain
            if !isMain { titles[i].name = [titles[i].disc, titles[i].playlist].filter { !$0.isEmpty }.joined(separator: " ") }
        }
    }

    static func scan(root: URL, label: String, mkvmerge: URL) async -> (Disc, [Title]) {
        let playlists = ((try? FileManager.default.contentsOfDirectory(
            at: root.appending(path: "BDMV/PLAYLIST"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "mpls" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // mkvmerge -J on a playlist reads clip headers; a few at once keeps the disk busy without thrashing.
        var titles: [Title] = []
        await withTaskGroup(of: Title?.self) { group in
            var pending = playlists.makeIterator()
            for _ in 0..<4 {
                guard let p = pending.next() else { break }
                group.addTask { await identify(p, disc: label, mkvmerge: mkvmerge) }
            }
            for await title in group {
                if let title { titles.append(title) }
                if let p = pending.next() { group.addTask { await identify(p, disc: label, mkvmerge: mkvmerge) } }
            }
        }
        titles.sort { $0.playlist < $1.playlist }

        // Many discs carry several playlists over the same clips; keep the lowest-numbered one.
        var unique: [Title] = []
        for t in titles {
            if let i = unique.firstIndex(where: { $0.clips == t.clips && abs($0.duration - t.duration) < 1 }) {
                unique[i].duplicates.append(t.playlist)
            } else {
                unique.append(t)
            }
        }

        // mkvmerge can't identify encrypted playlists, so check the largest stream file directly.
        let streams = (try? FileManager.default.contentsOfDirectory(
            at: root.appending(path: "BDMV/STREAM"), includingPropertiesForKeys: [.fileSizeKey])) ?? []
        func size(_ u: URL) -> Int { (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        let encrypted = streams.max { size($0) < size($1) }.map(isEncrypted) ?? false
        return (Disc(root: root, label: label, encrypted: encrypted), unique)
    }

    private static func identify(_ playlist: URL, disc: String, mkvmerge: URL) async -> Title? {
        guard let data = try? await Process.output(mkvmerge, ["-J", playlist.path]),
              let id = try? decoder.decode(Identification.self, from: data),
              let p = id.container.properties, let files = p.playlistFile, !files.isEmpty
        else { return nil }
        let tracks = (id.tracks ?? []).map { t in
            Track(id: t.id, type: t.type, codec: t.codec, language: t.properties.language ?? "und",
                  channels: t.properties.audioChannels, resolution: t.properties.pixelDimensions)
        }
        return Title(playlistURL: playlist, disc: disc, duration: Double(p.playlistDuration ?? 0) / 1e9,
                     size: p.playlistSize ?? 0, chapters: p.playlistChapters ?? 0, clips: files, tracks: tracks)
    }

    private static let decoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// The subset of `mkvmerge -J` output we use.
    private struct Identification: Decodable {
        struct Container: Decodable { let properties: Properties? }
        struct Properties: Decodable {
            let playlistDuration: Int64?  // nanoseconds
            let playlistSize: Int64?
            let playlistChapters: Int?
            let playlistFile: [String]?
        }
        struct Track: Decodable {
            struct Properties: Decodable {
                let language: String?
                let audioChannels: Int?
                let pixelDimensions: String?
            }
            let id: Int
            let type: String
            let codec: String
            let properties: Properties
        }
        let container: Container
        let tracks: [Track]?
    }
}

extension Process {
    /// Runs `exe` to completion and returns its stdout.
    static func output(_ exe: URL, _ args: [String]) async throws -> Data {
        try await Task.detached {
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            try p.run()
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            p.waitUntilExit()
            return data
        }.value
    }
}

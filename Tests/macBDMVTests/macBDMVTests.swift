import Foundation
import Testing
@testable import macBDMV

@Test(arguments: [
    ("/x/Parasite.2019.MULTi.COMPLETE.UHD.BLURAY-MMCLX", "Parasite (2019)"),
    ("/x/War and Peace (1966)/DISC01", "War and Peace (1966)"),
    ("/x/The_Thing_1982/BDMV", "The Thing (1982)"),
    ("/x/Some Movie", "Some Movie"),
])
func movieName(path: String, expected: String) {
    #expect(Scanner.movieName(for: URL(filePath: path)) == expected)
}

@Test func trackNames() {
    let dts = Track(id: 1, type: "audio", codec: "DTS-HD Master Audio", language: "rus", channels: 6, resolution: nil)
    let sub = Track(id: 2, type: "subtitles", codec: "HDMV PGS", language: "ger", channels: nil, resolution: nil)
    #expect(dts.displayName == "Russian - DTS-HD MA 5.1")
    #expect(sub.displayName == "German")
    let und = Track(id: 3, type: "audio", codec: "TrueHD Atmos", language: "und", channels: 8, resolution: nil)
    #expect(und.displayName == "TrueHD Atmos 7.1")
}

@Test func foreignAudioGetsDefaultSubtitles() {
    let t = Title(playlistURL: URL(filePath: "/d/BDMV/PLAYLIST/00001.mpls"), disc: "", duration: 1, size: 1, chapters: 1, clips: [],
                  tracks: [
                      Track(id: 0, type: "video", codec: "HEVC/H.265/MPEG-H", language: "und", channels: nil, resolution: "3840x2160"),
                      Track(id: 1, type: "audio", codec: "AC-3", language: "rus", channels: 6, resolution: nil),
                      Track(id: 2, type: "audio", codec: "AC-3", language: "eng", channels: 2, resolution: nil, keep: false),
                      Track(id: 3, type: "subtitles", codec: "HDMV PGS", language: "eng", channels: nil, resolution: nil),
                  ])
    let args = Remuxer.arguments(for: t, output: URL(filePath: "/o.mkv")).joined(separator: " ")
    #expect(args.contains("--audio-tracks 1 "))
    #expect(args.contains("--default-track-flag 1:1"))
    #expect(args.contains("--default-track-flag 3:1"))  // assumes an English-language test machine
}

/// End-to-end against a real BDMV folder: `BDMV_TEST_DISC=/path swift test`.
let testDisc = ProcessInfo.processInfo.environment["BDMV_TEST_DISC"]

@Test(.enabled(if: testDisc != nil))
@MainActor func cancelLeavesNoPartialFiles() async throws {
    let out = FileManager.default.temporaryDirectory.appending(path: "macBDMV-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: out) }
    let model = AppModel()
    model.outputDir = out
    await model.open(URL(filePath: testDisc!))
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    let run = Task { await model.start() }
    try await Task.sleep(for: .milliseconds(150))
    model.cancel()
    await run.value
    let files = FileManager.default.enumerator(atPath: out.path)?.allObjects as? [String] ?? []
    #expect(!files.contains { $0.hasSuffix(".part") })
    #expect(!model.running)
    #expect(model.titles.allSatisfy { $0.state == .idle || $0.state == .done }, "\(model.titles.map(\.state))")
}

@Test(.enabled(if: testDisc != nil))
@MainActor func flagsEncryptedDisc() async throws {
    let copy = FileManager.default.temporaryDirectory.appending(path: "macBDMV-enc-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: copy) }
    try FileManager.default.copyItem(at: URL(filePath: testDisc!), to: copy)
    let streams = try FileManager.default.contentsOfDirectory(at: copy.appending(path: "BDMV/STREAM"), includingPropertiesForKeys: nil)
    for m2ts in streams {
        let fh = try FileHandle(forUpdating: m2ts)
        try fh.seek(toOffset: 16)
        try fh.write(contentsOf: Data((0..<6128).map { _ in UInt8.random(in: 0...255) }))
        try fh.close()
    }
    let model = AppModel()
    await model.open(copy)
    #expect(!model.encryptedDiscs.isEmpty)
    #expect(!model.canStart)
}

@Test(.enabled(if: testDisc != nil))
@MainActor func remuxDisc() async throws {
    let disc = URL(filePath: testDisc!)
    let out = FileManager.default.temporaryDirectory.appending(path: "macBDMV-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: out) }

    let model = AppModel()
    model.outputDir = out
    await model.open(disc)
    #expect(!model.titles.isEmpty)
    #expect(model.encryptedDiscs.isEmpty)
    for t in model.titles { print(t.playlist, t.kind, t.selected, t.name, t.duration, t.duplicates) }

    for t in model.titles { model.binding(t, \.selected).wrappedValue = true }
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    await model.start()
    for t in model.titles {
        #expect(t.state == .done, "\(t.playlist): \(t.state)")
        #expect(FileManager.default.fileExists(atPath: model.outputURL(for: t).path))
    }
    let files = FileManager.default.enumerator(atPath: out.path)?.allObjects as? [String] ?? []
    print(files.sorted())
    #expect(!files.contains { $0.hasSuffix(".part") })

    // The main feature keeps chapters, gets named tracks and exactly one default audio track.
    let main = try #require(model.titles.first { $0.kind == .main })
    let data = try await Process.output(model.mkvmerge!, ["-J", model.outputURL(for: main).path])
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tracks = try #require(json["tracks"] as? [[String: Any]])
    let props = tracks.map { $0["properties"] as! [String: Any] }
    print(props.map { ($0["track_name"] ?? "", $0["default_track"] ?? "", $0["language"] ?? "") })
    #expect(tracks.count == main.tracks.count)
    #expect((json["chapters"] as? [[String: Any]])?.first?["num_entries"] as? Int == main.chapters)
    let audio = zip(tracks, props).filter { $0.0["type"] as? String == "audio" }.map(\.1)
    #expect(audio.filter { $0["default_track"] as? Bool == true }.count == 1)
    #expect(audio.allSatisfy { ($0["track_name"] as? String)?.contains(" - ") == true })
}

@Test func featureSelection() {
    func title(_ n: String, _ minutes: Double, _ clips: [String], disc: String = "") -> Title {
        Title(playlistURL: URL(filePath: "/d/\(n).mpls"), disc: disc, duration: minutes * 60, size: 1, chapters: 1, clips: clips, tracks: [])
    }
    var titles = [
        title("00001", 120, ["a", "b"]),               // theatrical cut
        title("00002", 130, ["a", "x", "b"]),          // extended cut: longest, wins
        title("00003", 100, ["c", "d"], disc: "D2"),   // part two on another disc
        title("00800", 20, ["e"]),                     // extra
    ]
    Scanner.markFeatures(&titles)
    #expect(titles.map(\.selected) == [false, true, true, false])
    #expect(titles.map(\.kind) == [.other, .main, .main, .other])
    #expect(titles[3].name == "00800")
}

@Test func detectsEncryptedStream() throws {
    let unit = 6144
    var clear = Data(count: unit * 2)
    for i in stride(from: 4, to: clear.count, by: 192) { clear[i] = 0x47 }
    var scrambled = clear
    for i in 16..<unit { scrambled[i] = UInt8.random(in: 0...255) }  // AACS leaves the first 16 bytes of a unit in the clear

    let dir = FileManager.default.temporaryDirectory
    let a = dir.appending(path: "clear.m2ts"), b = dir.appending(path: "scrambled.m2ts")
    defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
    try clear.write(to: a)
    try scrambled.write(to: b)
    #expect(!Scanner.isEncrypted(a))
    #expect(Scanner.isEncrypted(b))
}

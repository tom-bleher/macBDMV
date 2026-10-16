import Foundation

enum Remuxer {
    /// mkvmerge from Homebrew or the MKVToolNix app bundle; GUI apps don't inherit the shell's PATH.
    static func locate() -> URL? {
        let fm = FileManager.default
        let bundles = ((try? fm.contentsOfDirectory(atPath: "/Applications")) ?? [])
            .filter { $0.hasPrefix("MKVToolNix") }
            .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            .map { "/Applications/\($0)/Contents/MacOS/mkvmerge" }
        return (["/opt/homebrew/bin/mkvmerge", "/usr/local/bin/mkvmerge"] + bundles)
            .first(where: fm.isExecutableFile(atPath:))
            .map { URL(filePath: $0) }
    }

    /// Lossless remux of one playlist: chosen tracks only, named tracks, sane default flags. Chapters come along.
    static func arguments(for title: Title, output: URL) -> [String] {
        var args = ["--gui-mode", "-o", output.path, "--title", title.name]
        let kept = title.tracks.filter(\.keep)
        let audio = kept.filter { $0.type == "audio" }
        let subs = kept.filter { $0.type == "subtitles" }

        for (type, flag, none) in [("video", "--video-tracks", "--no-video"),
                                   ("audio", "--audio-tracks", "--no-audio"),
                                   ("subtitles", "--subtitle-tracks", "--no-subtitles")] {
            let ids = kept.filter { $0.type == type }.map { String($0.id) }
            args += ids.isEmpty ? [none] : [flag, ids.joined(separator: ",")]
        }

        // Subtitles default on only when the primary audio isn't in the user's language.
        let needsSubs = audio.first.map { !Language.same($0.language, Language.preferred) } ?? false
        let defaultSub = needsSubs ? subs.first { Language.same($0.language, Language.preferred) } : nil

        for t in audio {
            args += ["--track-name", "\(t.id):\(t.displayName)",
                     "--default-track-flag", "\(t.id):\(t.id == audio.first?.id ? 1 : 0)"]
        }
        for t in subs {
            args += ["--track-name", "\(t.id):\(t.displayName)",
                     "--default-track-flag", "\(t.id):\(t.id == defaultSub?.id ? 1 : 0)"]
        }
        return args + [title.playlistURL.path]
    }
}

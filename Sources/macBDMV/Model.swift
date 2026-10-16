import Foundation

struct Track: Identifiable, Hashable {
    let id: Int  // mkvmerge track ID
    let type: String  // "video", "audio", "subtitles"
    let codec: String
    let language: String  // ISO 639-2, "und" when unknown
    let channels: Int?
    let resolution: String?
    let forced: Bool
    var keep = true

    var detail: String {
        if let resolution { return resolution }
        if let channels { return Track.layout(channels) }
        return forced ? "Forced" : ""
    }

    /// Track name written into the MKV, e.g. "English - DTS-HD MA 5.1".
    var displayName: String {
        let lang = language == "und" ? nil : Language.name(language)
        switch type {
        case "audio": return [lang, "\(Track.shortCodec(codec)) \(detail)"].compactMap { $0 }.joined(separator: " - ")
        case "subtitles": return (lang ?? "Subtitles") + (forced ? " (Forced)" : "")
        default: return ""
        }
    }

    static func layout(_ channels: Int) -> String {
        switch channels {
        case 1: "1.0"
        case 2: "2.0"
        case 6: "5.1"
        case 8: "7.1"
        default: "\(channels)ch"
        }
    }

    static func shortCodec(_ codec: String) -> String {
        [
            "DTS-HD Master Audio": "DTS-HD MA", "DTS-HD High Resolution Audio": "DTS-HD HR",
            "AVC/H.264/MPEG-4p10": "H.264", "HEVC/H.265/MPEG-H": "HEVC", "MPEG-1/2": "MPEG-2",
            "HDMV PGS": "PGS",
        ][codec] ?? codec
    }
}

/// Plex/Jellyfin extras folders; `.main` goes at the top level.
enum Kind: String, CaseIterable, Identifiable {
    case main = "Main Feature"
    case featurette = "Featurettes"
    case interview = "Interviews"
    case behindTheScenes = "Behind The Scenes"
    case deleted = "Deleted Scenes"
    case trailer = "Trailers"
    case other = "Other"

    var id: Self { self }
}

enum JobState: Equatable {
    case idle, queued, running(Double), done, warning(String), failed(String)
}

struct Title: Identifiable {
    var id: URL { playlistURL }
    let playlistURL: URL
    let disc: String  // disc folder label, e.g. "DISC01"
    let duration: TimeInterval
    let size: Int64
    let chapters: Int
    let clips: [String]
    var duplicates: [String] = []
    var tracks: [Track]
    var selected = false
    var kind = Kind.other
    var name = ""
    var state = JobState.idle

    var playlist: String { playlistURL.deletingPathExtension().lastPathComponent }
}

enum Language {
    /// ISO 639-2/B codes mkvmerge reports that Foundation only knows in their /T form.
    private static let bibliographic = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho", "cze": "ces",
        "dut": "nld", "fre": "fra", "geo": "kat", "ger": "deu", "gre": "ell", "ice": "isl",
        "mac": "mkd", "may": "msa", "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod",
        "wel": "cym",
    ]

    static func name(_ code: String) -> String {
        if code == "und" { return "—" }
        let code = bibliographic[code] ?? code
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    /// The user's language as ISO 639-2, used to pick a default subtitle track.
    static var preferred: String {
        Locale.current.language.languageCode?.identifier(.alpha3) ?? "eng"
    }

    static func same(_ a: String, _ b: String) -> Bool {
        (bibliographic[a] ?? a) == (bibliographic[b] ?? b)
    }
}

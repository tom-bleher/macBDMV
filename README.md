# macBDMV

A small native macOS app that turns decrypted Blu-ray / UHD backups (`BDMV` folders) into MKV files. Nothing is re-encoded: video, audio, subtitles and chapters are copied bit-for-bit by [MKVToolNix](https://mkvtoolnix.download)'s `mkvmerge`.

## Requirements

- macOS 14+
- MKVToolNix: `brew install mkvtoolnix` (or the MKVToolNix app in `/Applications`)
- A **decrypted** backup. AACS-encrypted discs are detected and refused; decrypt them with MakeMKV's backup mode first.

## Build

```sh
scripts/build_app.sh            # → build/macBDMV.app
scripts/build_app.sh --install  # also copies it to /Applications
```

## Use

Drop a folder on the window or Dock icon (or `open -a macBDMV <folder>`). It can be a disc (`…/BDMV`), the folder above it, or a folder of several discs (`DISC01`, `DISC02`, …).

1. Every playlist is scanned. Playlists that use the same clips are merged into one row, and clips under 2 minutes are hidden unless you tick **Show short clips**.
2. Titles at least half as long as the longest one are marked **Main Feature** and selected. If there are several (a multi-part film), they become `Name - pt1`, `pt2`, ….
3. Tick any extras you want and give each a type and name. Pick a title to choose which of its tracks to keep.
4. Choose an output folder and click **Remux**.

Output follows Plex/Jellyfin conventions:

```
Movie (Year)/
├── Movie (Year).mkv
├── Featurettes/…
├── Interviews/…
└── Trailers/…
```

**Track metadata:**
- Audio tracks are named like `Russian - DTS-HD MA 5.1`.
- The first audio track you keep is the default.
- If that track isn't in your system language, a subtitle track in your language is made the default.
- Forced subtitle tracks keep the forced flag.
- Dolby Vision enhancement layers are merged by mkvmerge automatically.

**While remuxing:**
- Each file is written as `*.mkv.part` and renamed only after mkvmerge succeeds.
- Existing files are never overwritten.
- Cancelling deletes the partial file.

## Limitations

- **Playlist obfuscation** (some Disney and Lionsgate discs have hundreds of same-length playlists with shuffled clips) isn't solved; the app only shows a warning. Check runtime and chapters, or use MakeMKV for those discs.
- **BD+** protection isn't detected.

## Test

```sh
swift test                                   # unit tests
BDMV_TEST_DISC=/path/to/disc swift test      # + end-to-end remux of a real BDMV folder
```

# macBDMV

A small native macOS app that turns decrypted Blu-ray / UHD backups (`BDMV` folders) into MKV files. Nothing is re-encoded: video, audio, subtitles and chapters are copied bit-for-bit by [MKVToolNix](https://mkvtoolnix.download)'s `mkvmerge`.

## Requirements

- macOS 14+
- MKVToolNix: `brew install mkvtoolnix` (or the MKVToolNix app in `/Applications`)
- A **decrypted** backup. AACS-encrypted discs are detected and refused; decrypt them with MakeMKV's backup mode first.

## Install

Download the DMG from the [latest release](https://github.com/tom-bleher/macBDMV/releases/latest) and drag macBDMV to Applications. The app is not notarized, so open it the first time with right-click → Open (or System Settings → Privacy & Security → Open Anyway). After that it updates itself.

## Build

```sh
scripts/build_app.sh            # → build/macBDMV.app (Release, arm64, ad-hoc signed)
scripts/build_app.sh --install  # also copies it to /Applications
scripts/package-dmg.sh          # → dist/macBDMV-<version>.dmg, mounted, checked and launch-tested
```

## Updates

The app updates itself with [Sparkle 2](https://sparkle-project.org): it checks in the background, and you can check by hand from macBDMV ▸ Check for Updates…. The feed is the `appcast.xml` attached to the latest GitHub release. The DMG doubles as the update archive and is EdDSA-signed. To publish a release:

```sh
scripts/release.sh --version 1.1.0 --notes-file notes.md
```

`release.sh` does these steps:

1. Requires a clean checkout pushed to `origin/main`.
2. Builds and verifies the DMG.
3. Signs it with the Sparkle key and writes the appcast.
4. Refuses to continue unless the new build number (the commit count) sorts after the published one.
5. Creates the `vX.Y.Z` release with the DMG, its checksum and the appcast.

The EdDSA private key lives in the login keychain (account `macbdmv`), with a copy in `~/.config/macbdmv/sparkle-private-key`. The matching public key is `SUPublicEDKey` in `Resources/Info.plist`. Back the private key up: losing it strands every installed copy on its last update.

To test an update locally:
1. Serve a test appcast and DMG over HTTP.
2. Launch the app with `MACBDMV_FEED_URL=http://127.0.0.1:<port>/appcast.xml`.

## Use

Drop a folder on the window or Dock icon (or `open -a macBDMV <folder>`). It can be a disc (`…/BDMV`), the folder above it, or a folder of several discs (`DISC01`, `DISC02`, …).

1. Every playlist is scanned. Playlists that use the same clips are merged into one row, and clips under 2 minutes are hidden unless you tick **Show short clips**.
2. The longest title is selected as the **Main Feature**. Other titles at least half as long that share none of its clips (a film split across discs) are selected too and named `Name - pt1`, `pt2`, …. Alternate cuts that reuse the feature's clips are left unselected.
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
- Dolby Vision enhancement layers are merged by mkvmerge automatically.

**While remuxing:**
- Each file is written as `*.mkv.part` and renamed only after mkvmerge succeeds.
- Existing files are never overwritten.
- Cancelling or quitting deletes the partial file.

## Limitations

- **Playlist obfuscation** (some Disney and Lionsgate discs have hundreds of same-length playlists with shuffled clips) isn't solved; the app only shows a warning. Check runtime and chapters, or use MakeMKV for those discs.
- **BD+** protection isn't detected.

## Test

```sh
swift test                                   # unit tests
BDMV_TEST_DISC=/path/to/disc swift test      # + end-to-end remux of a real BDMV folder
```

## License

MIT — see [LICENSE](LICENSE).

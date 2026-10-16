import Sparkle
import SwiftUI

/// In-app updates via Sparkle 2: background checks plus macBDMV ▸ Check for Updates….
///
/// The feed (`SUFeedURL`, the appcast attached to the latest GitHub release) and the EdDSA public key
/// (`SUPublicEDKey`) come from Info.plist. Inactive when run outside the app bundle (`swift run`, tests).
@MainActor @Observable
final class SoftwareUpdate {
    static let shared = SoftwareUpdate()

    private(set) var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController?
    private let feedOverride = FeedOverride()
    private var observation: NSKeyValueObservation?

    private init() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: feedOverride,
                                                  userDriverDelegate: nil)
        observation = controller?.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let canCheck = change.newValue ?? false
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
}

/// Test hook: `MACBDMV_FEED_URL` replaces the feed, e.g. a local server holding a test appcast.
private final class FeedOverride: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["MACBDMV_FEED_URL"]
    }
}

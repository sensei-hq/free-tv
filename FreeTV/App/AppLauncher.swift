import UIKit

/// Opens provider apps. canOpenURL preflight drives the disabled state;
/// every open failure degrades to staying in-app (tvOS prompts the user
/// on first app switch, and refuses plain https with no handler).
/// Note: canOpenURL is deprecated in SDK 27 but not removed; there is
/// no replacement for install detection, so the warning is accepted.
enum AppLauncher {
    static func canOpen(_ url: URL) -> Bool {
        UIApplication.shared.canOpenURL(url)
    }

    static func openFirst(_ candidates: [URL]) {
        for url in candidates where canOpen(url) {
            UIApplication.shared.open(url)
            return
        }
    }
}

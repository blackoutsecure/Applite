import Foundation

enum CaskAdoptionError: LocalizedError {
    case notManaged

    var errorDescription: String? {
        String(localized: "Homebrew finished installing, but the app is not listed as managed. Refresh the app catalog to check again.")
    }
}

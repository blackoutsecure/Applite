import Foundation

enum ExternalAppDetector {
    /// Unlike launch resolution, detection never looks in the Caskroom or LaunchServices:
    /// stale receipts and registered apps on mounted disk images are not local installations.
    nonisolated static func appURL(
        bundleNames: [String],
        displayName: String,
        directories: [URL]
    ) -> URL? {
        let names = bundleNames.isEmpty ? ["\(displayName).app"] : bundleNames
        for directory in directories {
            for name in names {
                guard (name as NSString).lastPathComponent == name,
                      (name as NSString).pathExtension == "app" else { continue }
                let url = directory.appendingPathComponent(name, isDirectory: true)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    return url
                }
            }
        }
        return nil
    }
}

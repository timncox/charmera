import Foundation
import Photos

enum PhotosImporter {

    static func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
        default:
            completion(false)
        }
    }

    static func importFiles(_ paths: [String]) {
        guard !paths.isEmpty else { return }

        let posixFiles = paths.map { "POSIX file \"\($0)\"" }.joined(separator: ", ")

        let script = """
        tell application "Photos"
            if not (exists album "Charmera") then
                make new album named "Charmera"
            end if
            set theAlbum to album "Charmera"
            import {\(posixFiles)} into theAlbum skip check duplicates yes
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("[PhotosImporter] AppleScript error: \(error)")
            }
        }
    }
}

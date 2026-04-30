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

    /// Imports the given files into the user's Photos library and adds them to the "Charmera" album.
    /// Synchronous from the caller's POV — blocks until PhotoKit reports completion.
    /// Returns the count of files PhotoKit successfully imported.
    ///
    /// Replaces the old AppleScript implementation, which composed a single `import {...}`
    /// command with every file path. AppleEvents have a default 120s timeout and Photos.app
    /// import via AppleScript runs at ~30s/file under load — anything past ~4 files would silently
    /// time out and drop the rest of the batch.
    @discardableResult
    static func importFiles(_ paths: [String]) -> Int {
        guard !paths.isEmpty else { return 0 }

        let albumName = "Charmera"
        let album: PHAssetCollection
        do {
            album = try findOrCreateAlbum(named: albumName)
        } catch {
            print("[PhotosImporter] Could not find or create '\(albumName)' album: \(error)")
            return 0
        }

        var imported = 0
        for path in paths {
            let fileURL = URL(fileURLWithPath: path)
            let isVideo = ["mp4", "mov", "m4v"].contains(fileURL.pathExtension.lowercased())

            let semaphore = DispatchSemaphore(value: 0)
            var perFileSuccess = false
            var perFileError: Error?

            PHPhotoLibrary.shared().performChanges({
                let creationRequest: PHAssetCreationRequest? = {
                    if isVideo {
                        return PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                    } else {
                        return PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                    }
                }()

                guard let placeholder = creationRequest?.placeholderForCreatedAsset else { return }

                if let albumChange = PHAssetCollectionChangeRequest(for: album) {
                    albumChange.addAssets([placeholder] as NSArray)
                }
            }, completionHandler: { success, err in
                perFileSuccess = success
                perFileError = err
                semaphore.signal()
            })

            semaphore.wait()
            if perFileSuccess {
                imported += 1
            } else {
                let msg = perFileError?.localizedDescription ?? "unknown"
                print("[PhotosImporter] Failed to import \(fileURL.lastPathComponent): \(msg)")
            }
        }

        print("[PhotosImporter] Imported \(imported)/\(paths.count) into '\(albumName)' album")
        return imported
    }

    private static func findOrCreateAlbum(named name: String) throws -> PHAssetCollection {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", name)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
        if let existing = collections.firstObject {
            return existing
        }

        var placeholder: PHObjectPlaceholder?
        var creationError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = req.placeholderForCreatedAssetCollection
        }, completionHandler: { _, err in
            creationError = err
            semaphore.signal()
        })
        semaphore.wait()

        if let creationError = creationError { throw creationError }
        guard let id = placeholder?.localIdentifier else {
            throw NSError(domain: "PhotosImporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No placeholder for created album"])
        }
        let fetched = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
        guard let created = fetched.firstObject else {
            throw NSError(domain: "PhotosImporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Album was created but could not be re-fetched"])
        }
        return created
    }
}

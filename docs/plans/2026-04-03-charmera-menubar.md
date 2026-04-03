# Charmera Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app (Swift) that detects the Kodak Charmera camera, and on click: copies photos/videos to local backup, imports to Photos.app, converts videos to MP4, uploads to Vercel Blob, and posts metadata to charmera.vercel.app/api/import.

**Architecture:** Native Swift app using AppKit's NSStatusItem for the menu bar. FileManager for disk operations. Process for shelling out to ffmpeg. NSAppleScript for Photos.app import. URLSession for Vercel Blob uploads and API calls. DiskArbitration framework to detect camera mount/unmount.

**Tech Stack:** Swift 6, AppKit, Foundation, DiskArbitration, CryptoKit (SHA-256)

**Prerequisites:** The website (charmera-website plan) must be deployed first. The `BLOB_READ_WRITE_TOKEN` and `IMPORT_SECRET` values from Vercel are needed as hardcoded constants or a local config file.

---

## File Structure

```
charmera/app/
├── Charmera.xcodeproj/
├── Charmera/
│   ├── main.swift              # Entry point: NSApplication setup
│   ├── AppDelegate.swift       # NSStatusItem, menu setup, disk monitoring
│   ├── Importer.swift          # Core import pipeline: copy, convert, hash, upload, notify
│   ├── BlobUploader.swift      # Vercel Blob upload via direct PUT
│   ├── PhotosImporter.swift    # AppleScript bridge to Photos.app
│   ├── Config.swift            # Tokens, paths, constants
│   └── Assets.xcassets/
│       └── MenuBarIcon.imageset/  # 18x18 template icon for menu bar
├── Charmera.entitlements       # App Sandbox disabled (needs disk + Photos access)
└── Info.plist
```

---

### Task 1: Create Xcode Project

**Files:**
- Create: `charmera/app/` (Xcode project)

- [ ] **Step 1: Create the Swift package / Xcode project**

```bash
cd /Users/timcox/tim-os/charmera
mkdir -p app/Charmera
```

Create `app/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Charmera",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Charmera",
            path: "Charmera"
        ),
    ]
)
```

This uses Swift Package Manager instead of Xcode project — simpler to build from the command line.

- [ ] **Step 2: Create the entry point**

Create `app/Charmera/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Create a minimal AppDelegate that shows a menu bar icon**

Create `app/Charmera/AppDelegate.swift`:

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.title = "K"
            button.action = #selector(handleClick)
            button.target = self
        }

        // Don't show in Dock — menu bar only
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func handleClick() {
        NSLog("Charmera: menu bar clicked")
    }
}
```

- [ ] **Step 4: Build and run**

```bash
cd /Users/timcox/tim-os/charmera/app
swift build
.build/debug/Charmera &
```

Expected: A "K" appears in the macOS menu bar. Clicking it logs "Charmera: menu bar clicked" to the console. Kill with `kill %1`.

- [ ] **Step 5: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git add app/
git commit -m "feat: scaffold Swift menu bar app with Package.swift"
```

---

### Task 2: Config Constants

**Files:**
- Create: `charmera/app/Charmera/Config.swift`

- [ ] **Step 1: Create Config.swift with all constants**

Create `app/Charmera/Config.swift`:

```swift
import Foundation

enum Config {
    static let cameraVolumePath = "/Volumes/Charmera/DCIM"
    static let localBackupRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/Charmera")
    static let hashFilePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/Charmera/.imported-hashes")

    // These must be filled in from Vercel dashboard after website deployment
    static let blobToken = "YOUR_BLOB_READ_WRITE_TOKEN"
    static let importSecret = "YOUR_IMPORT_SECRET"
    static let importAPIURL = "https://charmera.vercel.app/api/import"

    // Vercel Blob upload endpoint — uses the unpathed API
    // See: https://vercel.com/docs/vercel-blob/using-blob-sdk#server-uploads
    static let blobUploadBase = "https://blob.vercel-storage.com"
}
```

Note: In a real scenario we'd read tokens from a config file or Keychain. For this personal tool, hardcoded constants are fine. The user should replace the placeholder values after deploying the website.

- [ ] **Step 2: Commit**

```bash
git add app/Charmera/Config.swift
git commit -m "feat: add config constants for paths and tokens"
```

---

### Task 3: Camera Detection + Icon State

**Files:**
- Modify: `charmera/app/Charmera/AppDelegate.swift`

- [ ] **Step 1: Add camera mount monitoring and icon color**

Replace `app/Charmera/AppDelegate.swift` with:

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.action = #selector(handleClick)
            button.target = self
        }

        NSApp.setActivationPolicy(.accessory)
        updateIcon()

        // Poll every 2 seconds for camera mount/unmount
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
    }

    private var isCameraConnected: Bool {
        FileManager.default.fileExists(atPath: Config.cameraVolumePath)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let attrs: [NSAttributedString.Key: Any]
        if isCameraConnected {
            attrs = [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor(red: 1.0, green: 0.718, blue: 0.0, alpha: 1.0), // #ffb700
            ]
        } else {
            attrs = [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.gray,
            ]
        }
        button.attributedTitle = NSAttributedString(string: "K", attributes: attrs)
    }

    @objc private func handleClick() {
        guard isCameraConnected else {
            showNotification(title: "Charmera", body: "No camera connected. Plug in your Charmera.")
            return
        }

        // Disable button during import
        statusItem.button?.isEnabled = false
        Task {
            do {
                let result = try await Importer.run()
                showNotification(
                    title: "Charmera",
                    body: "Imported \(result.photos) photo\(result.photos == 1 ? "" : "s"), \(result.videos) video\(result.videos == 1 ? "" : "s")"
                )
            } catch {
                showNotification(title: "Charmera", body: "Import failed: \(error.localizedDescription)")
            }
            await MainActor.run {
                statusItem.button?.isEnabled = true
            }
        }
    }

    private func showNotification(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(body)\" with title \"\(title)\""]
        try? process.run()
    }
}
```

- [ ] **Step 2: Create a stub Importer so it compiles**

Create `app/Charmera/Importer.swift`:

```swift
import Foundation

struct ImportResult {
    let photos: Int
    let videos: Int
}

enum Importer {
    static func run() async throws -> ImportResult {
        NSLog("Charmera: import pipeline starting...")
        return ImportResult(photos: 0, videos: 0)
    }
}
```

- [ ] **Step 3: Build and test**

```bash
cd /Users/timcox/tim-os/charmera/app
swift build
.build/debug/Charmera &
```

Expected: "K" in menu bar shows yellow when camera is plugged in, gray when not. Click when camera is disconnected shows "No camera connected" notification. Click when connected logs "import pipeline starting".

- [ ] **Step 4: Commit**

```bash
git add app/Charmera/AppDelegate.swift app/Charmera/Importer.swift
git commit -m "feat: camera detection with icon state and notification"
```

---

### Task 4: File Copy + Hash Dedup

**Files:**
- Modify: `charmera/app/Charmera/Importer.swift`

- [ ] **Step 1: Implement file discovery, hashing, and local copy**

Replace `app/Charmera/Importer.swift` with:

```swift
import Foundation
import CryptoKit

struct ImportResult {
    let photos: Int
    let videos: Int
}

struct CameraFile {
    let url: URL
    let hash: String
    let isVideo: Bool

    var filename: String { url.lastPathComponent }
}

enum Importer {
    static func run() async throws -> ImportResult {
        let dcimURL = URL(fileURLWithPath: Config.cameraVolumePath)
        let fm = FileManager.default

        // 1. Discover files
        let contents = try fm.contentsOfDirectory(at: dcimURL, includingPropertiesForKeys: nil)
        let mediaFiles = contents.filter { url in
            let name = url.lastPathComponent.uppercased()
            return name.hasSuffix(".JPG") || name.hasSuffix(".AVI")
        }

        if mediaFiles.isEmpty {
            return ImportResult(photos: 0, videos: 0)
        }

        // 2. Hash each file and filter already-imported
        let importedHashes = loadImportedHashes()
        var newFiles: [CameraFile] = []

        for fileURL in mediaFiles {
            let data = try Data(contentsOf: fileURL)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

            if !importedHashes.contains(hash) {
                let isVideo = fileURL.lastPathComponent.uppercased().hasPrefix("MOVI")
                newFiles.append(CameraFile(url: fileURL, hash: hash, isVideo: isVideo))
            }
        }

        if newFiles.isEmpty {
            return ImportResult(photos: 0, videos: 0)
        }

        // 3. Copy to local backup
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let backupDir = Config.localBackupRoot.appendingPathComponent(String(dateStr))
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        var copiedFiles: [(CameraFile, URL)] = [] // (original, local copy)
        for file in newFiles {
            let dest = backupDir.appendingPathComponent(file.filename)
            if !fm.fileExists(atPath: dest.path) {
                try fm.copyItem(at: file.url, to: dest)
            }
            copiedFiles.append((file, dest))
        }

        NSLog("Charmera: copied \(copiedFiles.count) files to \(backupDir.path)")

        // 4. Convert videos AVI -> MP4
        var uploadFiles: [(CameraFile, URL)] = [] // (metadata, file to upload)
        for (file, localURL) in copiedFiles {
            if file.isVideo {
                let mp4URL = localURL.deletingPathExtension().appendingPathExtension("mp4")
                try await convertToMP4(input: localURL, output: mp4URL)
                uploadFiles.append((file, mp4URL))
            } else {
                uploadFiles.append((file, localURL))
            }
        }

        // 5. Import to Photos.app
        let allLocalPaths = copiedFiles.map { $0.1.path }
        PhotosImporter.importToAlbum(paths: allLocalPaths, album: "Charmera")

        // 6. Upload to Vercel Blob and collect metadata
        var mediaItems: [[String: String]] = []
        for (file, uploadURL) in uploadFiles {
            let blobURL = try await BlobUploader.upload(fileURL: uploadURL, filename: file.isVideo
                ? file.filename.replacingOccurrences(of: ".avi", with: ".mp4", options: .caseInsensitive)
                : file.filename
            )
            let attrs = try fm.attributesOfItem(atPath: file.url.path)
            let created = (attrs[.creationDate] as? Date) ?? Date()

            mediaItems.append([
                "url": blobURL,
                "type": file.isVideo ? "video" : "photo",
                "timestamp": ISO8601DateFormatter().string(from: created),
                "hash": file.hash,
                "filename": file.isVideo
                    ? file.filename.replacingOccurrences(of: ".avi", with: ".mp4", options: .caseInsensitive)
                    : file.filename,
            ])
        }

        // 7. POST metadata to website
        try await postMetadata(items: mediaItems)

        // 8. Save hashes
        saveImportedHashes(importedHashes.union(Set(newFiles.map(\.hash))))

        let photos = newFiles.filter { !$0.isVideo }.count
        let videos = newFiles.filter { $0.isVideo }.count
        return ImportResult(photos: photos, videos: videos)
    }

    // MARK: - Video conversion

    private static func convertToMP4(input: URL, output: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-i", input.path,
            "-c:v", "libx264",
            "-preset", "fast",
            "-crf", "23",
            "-c:a", "aac",
            "-b:a", "128k",
            "-movflags", "+faststart",
            "-y",
            output.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Charmera", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ffmpeg failed with status \(process.terminationStatus)",
            ])
        }
        NSLog("Charmera: converted \(input.lastPathComponent) -> \(output.lastPathComponent)")
    }

    // MARK: - Hash persistence

    private static func loadImportedHashes() -> Set<String> {
        guard let data = try? Data(contentsOf: Config.hashFilePath),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map(String.init))
    }

    private static func saveImportedHashes(_ hashes: Set<String>) {
        let text = hashes.sorted().joined(separator: "\n")
        try? FileManager.default.createDirectory(
            at: Config.hashFilePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? text.write(to: Config.hashFilePath, atomically: true, encoding: .utf8)
    }

    // MARK: - API

    private static func postMetadata(items: [[String: String]]) async throws {
        let url = URL(string: Config.importAPIURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.importSecret)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["items": items])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "Charmera", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "API import failed: \(body)",
            ])
        }
        NSLog("Charmera: metadata posted successfully")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Charmera/Importer.swift
git commit -m "feat: full import pipeline — copy, hash, convert, upload, post"
```

---

### Task 5: Vercel Blob Uploader

**Files:**
- Create: `charmera/app/Charmera/BlobUploader.swift`

- [ ] **Step 1: Create the Blob uploader**

Create `app/Charmera/BlobUploader.swift`:

```swift
import Foundation

enum BlobUploader {
    /// Uploads a file to Vercel Blob using the REST API.
    /// Returns the public URL of the uploaded blob.
    static func upload(fileURL: URL, filename: String) async throws -> String {
        let data = try Data(contentsOf: fileURL)

        let uploadURL = URL(string: "\(Config.blobUploadBase)/charmera/\(filename)")!
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(Config.blobToken)", forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "x-api-blob-no-suffix")

        // Set content type
        let ext = fileURL.pathExtension.lowercased()
        let contentType: String
        switch ext {
        case "jpg", "jpeg": contentType = "image/jpeg"
        case "mp4": contentType = "video/mp4"
        case "avi": contentType = "video/x-msvideo"
        default: contentType = "application/octet-stream"
        }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: responseData, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "Charmera", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Blob upload failed for \(filename): \(body)",
            ])
        }

        // Parse the URL from the response JSON
        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        guard let blobURL = json?["url"] as? String else {
            throw NSError(domain: "Charmera", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "No URL in blob upload response",
            ])
        }

        NSLog("Charmera: uploaded \(filename) -> \(blobURL)")
        return blobURL
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Charmera/BlobUploader.swift
git commit -m "feat: add Vercel Blob uploader via REST API"
```

---

### Task 6: Photos.app Importer

**Files:**
- Create: `charmera/app/Charmera/PhotosImporter.swift`

- [ ] **Step 1: Create the AppleScript-based Photos importer**

Create `app/Charmera/PhotosImporter.swift`:

```swift
import Foundation

enum PhotosImporter {
    /// Import files into Photos.app under a named album.
    /// Creates the album if it doesn't exist.
    static func importToAlbum(paths: [String], album: String) {
        guard !paths.isEmpty else { return }

        // Build POSIX file list for AppleScript
        let fileList = paths.map { "POSIX file \"\($0)\"" }.joined(separator: ", ")

        let script = """
        tell application "Photos"
            if not (exists album "\(album)") then
                make new album named "\(album)"
            end if
            set theAlbum to album "\(album)"
            import {\(fileList)} into theAlbum skip check duplicates yes
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if let error = error {
            NSLog("Charmera: Photos import error: \(error)")
        } else {
            NSLog("Charmera: imported \(paths.count) files to Photos album '\(album)'")
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Charmera/PhotosImporter.swift
git commit -m "feat: add Photos.app importer via AppleScript"
```

---

### Task 7: Build, Test End-to-End, and Package

**Files:** None (build + test)

- [ ] **Step 1: Update Config.swift with real tokens**

After deploying the website (Task 11 of the website plan), copy the real `BLOB_READ_WRITE_TOKEN` and `IMPORT_SECRET` values from `.env.local` in the web project into `app/Charmera/Config.swift`.

- [ ] **Step 2: Build release binary**

```bash
cd /Users/timcox/tim-os/charmera/app
swift build -c release
```

Expected: builds successfully. Binary at `.build/release/Charmera`.

- [ ] **Step 3: Test with camera connected**

Plug in the Kodak Charmera via USB. Wait for it to mount at `/Volumes/Charmera`.

```bash
cd /Users/timcox/tim-os/charmera/app
.build/release/Charmera &
```

Click the yellow "K" in the menu bar. Expected:
1. Files copied to `~/Pictures/Charmera/2026-04-03/`
2. Videos converted to MP4
3. Photos.app opens briefly, files appear in "Charmera" album
4. Files uploaded to Vercel Blob
5. Metadata posted to charmera.vercel.app/api/import
6. Notification: "Charmera: Imported 20 photos, 1 video"

Reload charmera.vercel.app — all 21 media items should appear in the contact sheet grid.

- [ ] **Step 4: Test dedup — click again**

Click the "K" again with the same camera plugged in. Expected: Notification says "Imported 0 photos, 0 videos" (all hashes already recorded). No duplicates on the website.

- [ ] **Step 5: Set up login item (auto-start on boot)**

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {name:"Charmera", path:"/Users/timcox/tim-os/charmera/app/.build/release/Charmera", hidden:false}'
```

- [ ] **Step 6: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git add -A
git commit -m "feat: charmera menu bar app v1 complete"
```

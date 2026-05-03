import Foundation
import MCP
import CharmeraCore

// MARK: - Helpers

func text(_ s: String) -> Tool.Content {
    .text(text: s, annotations: nil, _meta: nil)
}

func jsonText(_ object: Any) -> Tool.Content {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    return text(String(data: data, encoding: .utf8) ?? "{}")
}

func errText(_ message: String) -> CallTool.Result {
    .init(content: [text(message)], isError: true)
}

/// Read a Keychain item via the `security` CLI. The MCP helper is signed
/// with a different identifier than Charmera.app, so it can't read tokens
/// directly via SecItemCopyMatching (the items live in a different access
/// group, and `keychain-access-groups` entitlements require a provisioning
/// profile that Developer ID signing doesn't bundle). The `security` CLI
/// goes through Security.framework with the user's login keychain — the
/// first read prompts the user, who can click "Always Allow."
func readKeychain(account: String, service: String = "com.charmera.app") -> String? {
    let proc = Process()
    let stdoutPipe = Pipe()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    proc.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
    proc.standardOutput = stdoutPipe
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        proc.waitUntilExit()
    } catch {
        return nil
    }
    guard proc.terminationStatus == 0 else { return nil }
    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func githubAuth() -> (token: String, username: String)? {
    guard let token = readKeychain(account: "github_token"),
          let username = readKeychain(account: "github_username") else { return nil }
    return (token, username)
}

// MARK: - Tool Definitions

let tools: [Tool] = [
    Tool(
        name: "detect_camera",
        description: "Check whether the Kodak Charmera camera is plugged in. Returns connection status and the path to the camera's DCIM directory if mounted.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    ),
    Tool(
        name: "list_camera_files",
        description: "List photo and video files currently on the camera's SD card. Does not copy or modify anything. Returns filename, size, and kind (photo/video) for each.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    ),
    Tool(
        name: "read_gallery_data",
        description: "Fetch the gallery's data.json from GitHub. Returns the array of all media entries (filename, url, type, hash, timestamp). Use this to answer questions about what has been imported.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    ),
    Tool(
        name: "rotate_photo",
        description: "Rotate a local photo file in place by 90, 180, or 270 degrees clockwise. Uses /usr/bin/sips. Operates on a local backup file path under ~/Pictures/Charmera.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"), "description": .string("Absolute path to the local photo file")]),
                "degrees": .object(["type": .string("integer"), "description": .string("Clockwise rotation in degrees: 90, 180, or 270"), "enum": .array([.int(90), .int(180), .int(270)])]),
            ]),
            "required": .array([.string("path"), .string("degrees")]),
        ])
    ),
    Tool(
        name: "push_to_gallery",
        description: "Upload, rotate, or delete files in the GitHub gallery in a single commit (one Pages build). Adds are local file paths uploaded to docs/media/. Deletes are gallery filenames (the bare name, not docs/media/<name>). Use appendEntries to add new rows to data.json — the server fetches the existing array, merges, and pushes the result, so you don't need to pass the whole gallery back through the tool call. removeEntryFilenames drops matching rows. dataJsonEntries (full replace) is still available for cases where you need to overwrite the whole array.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "adds": .object(["type": .string("array"), "items": .object(["type": .string("object"), "properties": .object(["localPath": .object(["type": .string("string")]), "galleryFilename": .object(["type": .string("string")])])])]),
                "deletes": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "message": .object(["type": .string("string"), "description": .string("Commit message")]),
                "appendEntries": .object(["type": .string("array"), "description": .string("Recommended for new uploads. New data.json rows to append; the server merges with the existing array. Each entry is {type, filename, url, hash, timestamp}.")]),
                "removeEntryFilenames": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "description": .string("Filenames to drop from data.json during the merge. Independent of `deletes` (which removes the file blob).")]),
                "dataJsonEntries": .object(["type": .string("array"), "description": .string("Escape hatch: if provided, replaces docs/data.json wholesale with these entries. Prefer appendEntries + removeEntryFilenames for normal flows."), "deprecated": .bool(true)]),
            ]),
            "required": .array([.string("message")]),
        ])
    ),
    Tool(
        name: "import_roll",
        description: "Run the full Charmera import pipeline: detect camera, copy new files, fix orientation, convert AVI→MP4, and push to the GitHub gallery in a single commit. By default skips Photos.app integration (the menu-bar Charmera.app handles that). Returns counts and any errors.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "skipPhotosImport": .object(["type": .string("boolean"), "description": .string("Skip the Photos.app step (default true for MCP — the .app handles it)"), "default": .bool(true)]),
                "skipVideoConversion": .object(["type": .string("boolean"), "description": .string("Skip AVI→MP4 conversion (default false)"), "default": .bool(false)]),
            ]),
        ])
    ),
    Tool(
        name: "read_video_frame",
        description: "Extract the first frame of a local video and return it as image content so the model can evaluate orientation. Use before deciding whether to call rotate_video. Path is the absolute filesystem path to an .mp4 (or any ffmpeg-readable video).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"), "description": .string("Absolute path to a local video")]),
            ]),
            "required": .array([.string("path")]),
        ])
    ),
    Tool(
        name: "rotate_video",
        description: "Rotate a local video file by 90, 180, or 270 degrees clockwise. Re-encodes via ffmpeg with -vf transpose; slower than rotate_photo but rare. Operates in place — the file is replaced atomically on success. Use only when convertAVItoMP4's auto-orient picked the wrong rotation.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"), "description": .string("Absolute path to a local .mp4")]),
                "degrees": .object(["type": .string("integer"), "description": .string("Clockwise rotation: 90, 180, or 270"), "enum": .array([.int(90), .int(180), .int(270)])]),
            ]),
            "required": .array([.string("path"), .string("degrees")]),
        ])
    ),
    Tool(
        name: "read_photo",
        description: "Read a local photo file and return it as image content so the model can see it. Use this to evaluate orientation, blur, composition, etc. before pushing to the gallery or Photos.app. Path is the absolute filesystem path (typically under ~/Pictures/Charmera/<date>/).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"), "description": .string("Absolute path to a local photo")]),
            ]),
            "required": .array([.string("path")]),
        ])
    ),
    Tool(
        name: "import_to_photos",
        description: "Import the given local files into the user's Photos.app library, adding them to the 'Charmera' album. Delegates to Charmera.app (which owns the Photos.app TCC scope) — make sure /Applications/Charmera.app is installed. Returns a JSON summary with imported/requested counts.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "paths": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "description": .string("Absolute paths of photos/videos to import")]),
            ]),
            "required": .array([.string("paths")]),
        ])
    ),
    Tool(
        name: "prepare_camera_import",
        description: "Phase 1 of a curated import: copy new photos+videos from the camera to a local backup folder WITHOUT auto-orientation, GitHub upload, or Photos.app import. Returns the list of local paths the model can read_photo + rotate_photo, then push via push_to_gallery + import_to_photos. Updates the imported-hashes file so a later import_roll won't double-copy.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "skipVideoConversion": .object(["type": .string("boolean"), "description": .string("Skip AVI→MP4 conversion (default false)"), "default": .bool(false)]),
            ]),
        ])
    ),
    Tool(
        name: "auth_status",
        description: "Check whether the Charmera GitHub credentials are present in the user's Keychain. Returns the GitHub username and gallery repo info if signed in.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    ),
]

// MARK: - Server

let server = Server(
    name: "charmera-mcp",
    version: "0.1.0",
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: tools)
}

await server.withMethodHandler(CallTool.self) { params in
    switch params.name {

    case "detect_camera":
        if let path = Config.cameraVolumePath {
            return .init(content: [jsonText(["connected": true, "mountPath": path])], isError: false)
        }
        return .init(content: [jsonText(["connected": false])], isError: false)

    case "list_camera_files":
        guard let cameraPath = Config.cameraVolumePath else {
            return errText("No camera connected.")
        }
        let fm = FileManager.default
        let dcimURL = URL(fileURLWithPath: cameraPath)
        var files: [[String: Any]] = []
        let enumerator = fm.enumerator(at: dcimURL, includingPropertiesForKeys: [.fileSizeKey])
        while let url = enumerator?.nextObject() as? URL {
            let name = url.lastPathComponent
            let upper = name.uppercased()
            let isPhoto = upper.hasPrefix("PICT") && upper.hasSuffix(".JPG")
            let isVideo = upper.hasPrefix("MOVI") && upper.hasSuffix(".AVI")
            guard isPhoto || isVideo else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            files.append([
                "name": name,
                "size": size,
                "kind": isPhoto ? "photo" : "video",
            ])
        }
        return .init(content: [jsonText(["files": files, "count": files.count])], isError: false)

    case "read_gallery_data":
        guard let auth = githubAuth() else {
            return errText("Not signed in to GitHub. Open the Charmera menu-bar app to authenticate.")
        }
        let api = GitHubAPI(token: auth.token)
        guard let data = api.downloadFile(owner: auth.username, repo: Config.repoName, path: "docs/data.json") else {
            return errText("Could not download docs/data.json from \(auth.username)/\(Config.repoName).")
        }
        let str = String(data: data, encoding: .utf8) ?? "[]"
        return .init(content: [text(str)], isError: false)

    case "rotate_photo":
        guard let path = params.arguments?["path"]?.stringValue,
              let degrees = params.arguments?["degrees"]?.intValue else {
            return errText("Missing 'path' or 'degrees'.")
        }
        guard [90, 180, 270].contains(degrees) else {
            return errText("'degrees' must be 90, 180, or 270.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return errText("File not found: \(path)")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        proc.arguments = ["-r", String(degrees), path, "--out", path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                return errText("sips returned non-zero status: \(proc.terminationStatus)")
            }
        } catch {
            return errText("sips failed: \(error.localizedDescription)")
        }
        return .init(content: [jsonText(["rotated": true, "path": path, "degrees": degrees])], isError: false)

    case "push_to_gallery":
        guard let auth = githubAuth() else {
            return errText("Not signed in to GitHub.")
        }
        guard let message = params.arguments?["message"]?.stringValue else {
            return errText("Missing 'message'.")
        }
        let api = GitHubAPI(token: auth.token)

        // Build adds
        var filesToUpload: [(path: String, content: Data)] = []
        if let addsArray = params.arguments?["adds"]?.arrayValue {
            for entry in addsArray {
                guard let dict = entry.objectValue,
                      let local = dict["localPath"]?.stringValue,
                      let gallery = dict["galleryFilename"]?.stringValue,
                      let data = FileManager.default.contents(atPath: local) else { continue }
                filesToUpload.append((path: "docs/media/\(gallery)", content: data))
            }
        }

        // Build deletes
        var deletes: [String] = []
        if let delArray = params.arguments?["deletes"]?.arrayValue {
            for v in delArray {
                if let s = v.stringValue { deletes.append("docs/media/\(s)") }
            }
        }

        // Helper: flatten an MCP Value array of objects into [[String: Any]] of strings.
        func flattenEntries(_ values: [Value]) -> [[String: Any]] {
            return values.compactMap { v in
                guard let obj = v.objectValue else { return nil }
                var dict: [String: Any] = [:]
                for (k, vv) in obj {
                    if let s = vv.stringValue { dict[k] = s }
                    else if let i = vv.intValue { dict[k] = i }
                    else if let b = vv.boolValue { dict[k] = b }
                }
                return dict
            }
        }

        let appendEntries = params.arguments?["appendEntries"]?.arrayValue.map(flattenEntries) ?? []
        var removeFilenames = Set<String>()
        if let arr = params.arguments?["removeEntryFilenames"]?.arrayValue {
            for v in arr { if let s = v.stringValue { removeFilenames.insert(s) } }
        }
        let fullReplace = params.arguments?["dataJsonEntries"]?.arrayValue.map(flattenEntries)

        // Build the new data.json. Three modes:
        //   1. dataJsonEntries provided → wholesale replace (legacy escape hatch).
        //   2. appendEntries / removeEntryFilenames provided → fetch current, merge.
        //   3. neither → don't touch data.json.
        if let replacement = fullReplace {
            if let json = try? JSONSerialization.data(withJSONObject: replacement, options: [.prettyPrinted, .sortedKeys]) {
                filesToUpload.append((path: "docs/data.json", content: json))
            }
        } else if !appendEntries.isEmpty || !removeFilenames.isEmpty {
            // Fold deleted blobs into the entry-removal set so a single `deletes` arg
            // also drops the corresponding data.json row.
            for path in deletes {
                let basename = (path as NSString).lastPathComponent
                removeFilenames.insert(basename)
            }
            // Pull current array, drop matching filenames, append new ones.
            var existing: [[String: Any]] = []
            if let data = api.downloadFile(owner: auth.username, repo: Config.repoName, path: "docs/data.json"),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                existing = arr
            }
            existing.removeAll { entry in
                guard let f = entry["filename"] as? String else { return false }
                return removeFilenames.contains(f)
            }
            // De-dupe new appends against existing filenames so re-runs don't double-list.
            let existingNames = Set(existing.compactMap { $0["filename"] as? String })
            let toAppend = appendEntries.filter {
                guard let f = $0["filename"] as? String else { return false }
                return !existingNames.contains(f)
            }
            let merged = existing + toAppend
            if let json = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]) {
                filesToUpload.append((path: "docs/data.json", content: json))
            }
        }

        guard !filesToUpload.isEmpty || !deletes.isEmpty else {
            return errText("Nothing to push: provide at least one of adds, deletes, appendEntries, removeEntryFilenames, or dataJsonEntries.")
        }

        do {
            let sha = try api.uploadFilesAsOneCommit(
                owner: auth.username,
                repo: Config.repoName,
                branch: "main",
                files: filesToUpload,
                deletions: deletes,
                message: message
            )
            return .init(content: [jsonText([
                "commit": sha,
                "uploaded": filesToUpload.count,
                "deleted": deletes.count,
                "pagesUrl": "https://\(auth.username).github.io/\(Config.repoName)/",
            ])], isError: false)
        } catch {
            return errText("Push failed: \(error.localizedDescription)")
        }

    case "import_roll":
        let skipPhotos = params.arguments?["skipPhotosImport"]?.boolValue ?? true
        let skipVideo = params.arguments?["skipVideoConversion"]?.boolValue ?? false
        let importer = Importer()
        var statusLog: [String] = []
        importer.onStatus = { statusLog.append($0) }
        let result = importer.run(reviewOnly: false, skipVideoConversion: skipVideo, skipPhotosImport: skipPhotos)
        switch result {
        case .success(let counts):
            return .init(content: [jsonText([
                "photos": counts.photos,
                "videos": counts.videos,
                "skippedPhotosApp": skipPhotos,
                "status": statusLog,
            ])], isError: false)
        case .failure(let error):
            return errText("Import failed: \(error.localizedDescription)")
        }

    case "read_video_frame":
        guard let path = params.arguments?["path"]?.stringValue else {
            return errText("Missing 'path'.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return errText("File not found: \(path)")
        }
        let framePath = "\(NSTemporaryDirectory())charmera-frame-\(UUID().uuidString).jpg"
        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: FFmpegManager.resolvedPath)
        extract.arguments = ["-y", "-i", path, "-vframes", "1", framePath]
        extract.standardOutput = FileHandle.nullDevice
        extract.standardError = FileHandle.nullDevice
        do {
            try extract.run()
            extract.waitUntilExit()
        } catch {
            return errText("ffmpeg launch failed: \(error.localizedDescription) (try: brew install ffmpeg)")
        }
        defer { try? FileManager.default.removeItem(atPath: framePath) }
        guard extract.terminationStatus == 0,
              let data = FileManager.default.contents(atPath: framePath) else {
            return errText("ffmpeg could not extract a frame from \(path)")
        }
        return .init(content: [.image(data: data.base64EncodedString(), mimeType: "image/jpeg", annotations: nil, _meta: nil)], isError: false)

    case "rotate_video":
        guard let path = params.arguments?["path"]?.stringValue,
              let degrees = params.arguments?["degrees"]?.intValue else {
            return errText("Missing 'path' or 'degrees'.")
        }
        guard [90, 180, 270].contains(degrees) else {
            return errText("'degrees' must be 90, 180, or 270.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return errText("File not found: \(path)")
        }
        let transpose: String
        switch degrees {
        case 90:  transpose = "transpose=1"
        case 180: transpose = "transpose=2,transpose=2"
        case 270: transpose = "transpose=2"
        default:  transpose = "transpose=1"
        }
        let tmpOut = "\(path).rotating-\(UUID().uuidString).mp4"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: FFmpegManager.resolvedPath)
        proc.arguments = ["-y", "-i", path, "-vf", transpose, "-c:v", "h264_videotoolbox", "-b:v", "2M", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", tmpOut]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return errText("ffmpeg launch failed: \(error.localizedDescription)")
        }
        guard proc.terminationStatus == 0,
              FileManager.default.fileExists(atPath: tmpOut) else {
            try? FileManager.default.removeItem(atPath: tmpOut)
            return errText("ffmpeg failed (status \(proc.terminationStatus))")
        }
        do {
            _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmpOut))
        } catch {
            try? FileManager.default.removeItem(atPath: tmpOut)
            return errText("Could not replace original: \(error.localizedDescription)")
        }
        return .init(content: [jsonText(["rotated": true, "path": path, "degrees": degrees])], isError: false)

    case "read_photo":
        guard let path = params.arguments?["path"]?.stringValue else {
            return errText("Missing 'path'.")
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            return errText("Could not read file: \(path)")
        }
        let ext = (path as NSString).pathExtension.lowercased()
        let mime: String
        switch ext {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "png":         mime = "image/png"
        case "heic":        mime = "image/heic"
        default:            mime = "application/octet-stream"
        }
        let b64 = data.base64EncodedString()
        return .init(content: [.image(data: b64, mimeType: mime, annotations: nil, _meta: nil)], isError: false)

    case "import_to_photos":
        guard let pathsArr = params.arguments?["paths"]?.arrayValue else {
            return errText("Missing 'paths' array.")
        }
        let paths: [String] = pathsArr.compactMap { $0.stringValue }
        guard !paths.isEmpty else {
            return errText("'paths' is empty.")
        }
        let charmeraBin = "/Applications/Charmera.app/Contents/MacOS/Charmera"
        guard FileManager.default.isExecutableFile(atPath: charmeraBin) else {
            return errText("Charmera.app not installed at /Applications/Charmera.app — install via `brew install --cask timncox/charmera/charmera` or build locally.")
        }
        let proc = Process()
        let stdoutPipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: charmeraBin)
        proc.arguments = ["--import-photos"] + paths
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return errText("Charmera --import-photos failed to launch: \(error.localizedDescription)")
        }
        let out = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .init(content: [text(outStr.isEmpty ? "{}" : outStr)], isError: proc.terminationStatus != 0)

    case "prepare_camera_import":
        let skipVideo = params.arguments?["skipVideoConversion"]?.boolValue ?? false
        let importer = Importer()
        var statusLog: [String] = []
        importer.onStatus = { statusLog.append($0) }
        let result = importer.run(
            reviewOnly: false,
            skipVideoConversion: skipVideo,
            skipPhotosImport: true,
            skipOrientation: true,
            skipUpload: true
        )
        switch result {
        case .success(let counts):
            return .init(content: [jsonText([
                "photos": counts.photos,
                "videos": counts.videos,
                "localPaths": counts.localPaths,
                "status": statusLog,
                "nextSteps": "For each photo: read_photo → rotate_photo (if needed). Then push_to_gallery + import_to_photos with the final paths.",
            ])], isError: false)
        case .failure(let error):
            return errText("prepare_camera_import failed: \(error.localizedDescription)")
        }

    case "auth_status":
        guard let auth = githubAuth() else {
            return .init(content: [jsonText(["signedIn": false])], isError: false)
        }
        return .init(content: [jsonText([
            "signedIn": true,
            "username": auth.username,
            "repo": Config.repoName,
            "galleryUrl": "https://\(auth.username).github.io/\(Config.repoName)/",
        ])], isError: false)

    default:
        return errText("Unknown tool: \(params.name)")
    }
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()

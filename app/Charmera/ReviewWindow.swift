import SwiftUI
import AppKit
import CharmeraCore

// MARK: - Review Data Model

class ReviewPhoto: Identifiable, ObservableObject {
    let id = UUID()
    let filePath: String
    let filename: String
    let dateFolder: String
    /// Size of the local file at the moment we loaded the review window. We snapshot it
    /// because a sips rotate later in `applyChanges` rewrites the file with a different
    /// size — and the data.json hash key is `<filename>:<original-camera-size>`. Reading
    /// the post-rotation size would miss the mapping and silently clobber an unrelated
    /// older PICT0040.jpg-style entry.
    let originalSize: Int64
    weak var parent: ReviewViewModel?
    @Published var rotation: Int = 0 { // 0, 90, 180, 270
        didSet { parent?.objectWillChange.send() }
    }
    @Published var markedForDeletion: Bool = false {
        didSet { parent?.objectWillChange.send() }
    }

    var image: NSImage? {
        NSImage(contentsOfFile: filePath)
    }

    /// Lookup key into data.json's hash field. Stable across rotations.
    var dataKey: String {
        "\(filename):\(originalSize)"
    }

    init(filePath: String, dateFolder: String) {
        self.filePath = filePath
        self.filename = URL(fileURLWithPath: filePath).lastPathComponent
        self.dateFolder = dateFolder
        let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
        self.originalSize = (attrs?[.size] as? Int64) ?? (attrs?[.size] as? Int).map(Int64.init) ?? 0
    }

    func rotate90() {
        rotation = (rotation + 90) % 360
    }
}

// MARK: - ReviewViewModel

class ReviewViewModel: ObservableObject {
    @Published var photos: [ReviewPhoto] = []
    @Published var isSaving = false
    @Published var saveMessage: String?

    init() {
        loadPhotos()
    }

    func loadPhotos() {
        let fm = FileManager.default
        let baseDir = Config.localBackupRoot
        var allPhotos: [ReviewPhoto] = []

        guard let dateFolders = try? fm.contentsOfDirectory(atPath: baseDir) else { return }

        for folder in dateFolders.sorted().reversed() {
            let folderPath = "\(baseDir)/\(folder)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
            for file in files.sorted() {
                let ext = (file as NSString).pathExtension.lowercased()
                guard ext == "jpg" || ext == "jpeg" else { continue }
                allPhotos.append(ReviewPhoto(filePath: "\(folderPath)/\(file)", dateFolder: folder))
            }
        }

        // Dedupe by filename — keep the newest version
        var seen: [String: ReviewPhoto] = [:]
        for photo in allPhotos {
            if let existing = seen[photo.filename] {
                // Keep whichever has a newer modification date
                let existingMod = (try? FileManager.default.attributesOfItem(atPath: existing.filePath))?[.modificationDate] as? Date ?? .distantPast
                let newMod = (try? FileManager.default.attributesOfItem(atPath: photo.filePath))?[.modificationDate] as? Date ?? .distantPast
                if newMod > existingMod {
                    seen[photo.filename] = photo
                }
            } else {
                seen[photo.filename] = photo
            }
        }
        let deduped = seen.values.sorted { $0.filename < $1.filename }
        for photo in deduped { photo.parent = self }
        photos = deduped
    }

    var hasChanges: Bool {
        photos.contains { $0.rotation != 0 || $0.markedForDeletion }
    }

    /// Find the actual repo path for a photo. The local backup keeps the camera's
    /// original filename (e.g. PICT0009.jpg), but on remote-name collision the importer
    /// renames the upload (e.g. PICT0009_2026-04-30.jpg) and only records the mapping in
    /// data.json's `hash` field (`<originalName>:<size>`). Look up there first so we
    /// always target the correct gallery file — using the local filename blindly would
    /// hit an unrelated older entry and corrupt it.
    private func resolveRepoPath(api: GitHubAPI, owner: String, photo: ReviewPhoto, dataMap: [String: String]) -> (path: String, sha: String)? {
        // Use the size we snapshot at load time — sips rotates rewrite the file with a
        // different size, which would miss data.json's hash key and silently clobber an
        // unrelated older photo with the same camera filename.
        let key = photo.dataKey
        if let mapped = dataMap[key] {
            let mappedPath = "docs/media/\(mapped)"
            if let sha = api.getFileSHA(owner: owner, repo: Config.repoName, path: mappedPath) {
                return (mappedPath, sha)
            }
        }
        // Fall back to filename-based lookup for older uploads that predate the hash field.
        let flatPath = "docs/media/\(photo.filename)"
        if let sha = api.getFileSHA(owner: owner, repo: Config.repoName, path: flatPath) {
            return (flatPath, sha)
        }
        let datePath = "docs/media/\(photo.dateFolder)/\(photo.filename)"
        if let sha = api.getFileSHA(owner: owner, repo: Config.repoName, path: datePath) {
            return (datePath, sha)
        }
        return nil
    }

    /// Build a lookup from `<cameraFilename>:<size>` (the importer's hash field) to the
    /// gallery filename it was uploaded as. Empty if data.json is unreachable; callers
    /// should still fall back to filename-based resolution in that case.
    private func loadDataJSONMap(api: GitHubAPI, owner: String) -> [String: String] {
        guard let data = api.downloadFile(owner: owner, repo: Config.repoName, path: "docs/data.json"),
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: String]] else {
            return [:]
        }
        var map: [String: String] = [:]
        for e in entries {
            if let h = e["hash"], let f = e["filename"] {
                map[h] = f
            }
        }
        return map
    }

    func applyChanges() {
        isSaving = true
        let rotated = photos.filter { $0.rotation != 0 && !$0.markedForDeletion }
        let deleted = photos.filter { $0.markedForDeletion }

        guard !rotated.isEmpty || !deleted.isEmpty else {
            saveMessage = "No changes to apply."
            isSaving = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Step 1: rotate locally with sips. Failures are real — surface them.
            var sipsErrors: [String] = []
            var rotatedSucceeded: [ReviewPhoto] = []
            for photo in rotated {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-c", "/usr/bin/sips -r \(photo.rotation) '\(photo.filePath)' --out '\(photo.filePath)'"]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        rotatedSucceeded.append(photo)
                    } else {
                        sipsErrors.append("\(photo.filename) (sips exit \(proc.terminationStatus))")
                    }
                } catch {
                    sipsErrors.append("\(photo.filename) (\(error.localizedDescription))")
                }
            }

            // Step 2: build one batched commit — rotated photos as adds, deleted photos as deletions,
            // and data.json reconciled to the post-state — instead of N separate commits that
            // overwhelm the Pages legacy builder.
            var uploadError: String?
            var deleteCount = 0
            var rotateCount = 0
            if let token = KeychainHelper.githubToken,
               let username = KeychainHelper.githubUsername {
                let api = GitHubAPI(token: token)
                let dataMap = self?.loadDataJSONMap(api: api, owner: username) ?? [:]

                // Resolve every affected file's actual repo path. data.json's `hash` field
                // (set during import) maps camera-filename:size to the gallery filename — so
                // collisions like local PICT0009.jpg → gallery PICT0009_2026-04-30.jpg are
                // resolved correctly here instead of clobbering an unrelated older entry.
                var addFiles: [(path: String, content: Data)] = []
                for photo in rotatedSucceeded {
                    guard let fileData = FileManager.default.contents(atPath: photo.filePath),
                          let resolved = self?.resolveRepoPath(api: api, owner: username, photo: photo, dataMap: dataMap) else {
                        sipsErrors.append("\(photo.filename) (could not resolve remote path)")
                        continue
                    }
                    addFiles.append((path: resolved.path, content: fileData))
                }

                var deletePaths: [String] = []
                var resolvedDeletions: [(photo: ReviewPhoto, path: String)] = []
                for photo in deleted {
                    if let resolved = self?.resolveRepoPath(api: api, owner: username, photo: photo, dataMap: dataMap) {
                        deletePaths.append(resolved.path)
                        resolvedDeletions.append((photo: photo, path: resolved.path))
                    } else {
                        sipsErrors.append("\(photo.filename) (could not resolve remote path)")
                    }
                }

                // Reconcile data.json: drop entries for deleted files.
                if !deletePaths.isEmpty {
                    if let data = api.downloadFile(owner: username, repo: Config.repoName, path: "docs/data.json"),
                       let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: String]] {
                        let deletedBasenames = Set(deletePaths.map { ($0 as NSString).lastPathComponent })
                        let filtered = entries.filter { entry in
                            guard let url = entry["url"] else { return false }
                            return !deletedBasenames.contains((url as NSString).lastPathComponent)
                        }
                        if let jsonData = try? JSONSerialization.data(withJSONObject: filtered, options: [.prettyPrinted, .sortedKeys]) {
                            addFiles.append((path: "docs/data.json", content: jsonData))
                        }
                    }
                }

                if !addFiles.isEmpty || !deletePaths.isEmpty {
                    let parts = [
                        rotatedSucceeded.isEmpty ? nil : "rotate \(rotatedSucceeded.count)",
                        deletePaths.isEmpty ? nil : "delete \(deletePaths.count)",
                    ].compactMap { $0 }
                    do {
                        _ = try api.uploadFilesAsOneCommit(
                            owner: username,
                            repo: Config.repoName,
                            branch: "main",
                            files: addFiles,
                            deletions: deletePaths,
                            message: "Review: \(parts.joined(separator: ", "))"
                        )
                        rotateCount = rotatedSucceeded.count
                        deleteCount = resolvedDeletions.count
                        for entry in resolvedDeletions {
                            try? FileManager.default.removeItem(atPath: entry.photo.filePath)
                        }
                    } catch {
                        uploadError = error.localizedDescription
                    }
                }
            }

            let appliedDeletedIDs = uploadError == nil ? Set(deleted.map { $0.id }) : Set<UUID>()
            DispatchQueue.main.async {
                self?.isSaving = false
                if let err = uploadError {
                    self?.saveMessage = "Upload failed: \(err)"
                    return
                }
                var parts: [String] = []
                if rotateCount > 0 { parts.append("Rotated \(rotateCount) photo(s)") }
                if deleteCount > 0 { parts.append("Deleted \(deleteCount) photo(s) from gallery") }
                if !sipsErrors.isEmpty {
                    parts.append("Skipped \(sipsErrors.count): \(sipsErrors.prefix(3).joined(separator: ", "))")
                }
                self?.saveMessage = parts.isEmpty ? "No changes to apply." : (parts.joined(separator: ". ") + ".")
                for photo in rotatedSucceeded { photo.rotation = 0 }
                self?.photos.removeAll { appliedDeletedIDs.contains($0.id) }
            }
        }
    }

    func uploadAll() {
        isSaving = true
        saveMessage = nil
        let photosToUpload = photos.filter { !$0.markedForDeletion }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let token = KeychainHelper.githubToken,
                  let username = KeychainHelper.githubUsername else {
                DispatchQueue.main.async {
                    self?.isSaving = false
                    self?.saveMessage = "Not signed in."
                }
                return
            }

            let api = GitHubAPI(token: token)
            let isoFormatter = ISO8601DateFormatter()
            let fm = FileManager.default
            var uploadCount = 0
            var newEntries: [[String: String]] = []

            // Import to Photos.app if enabled
            let importToPhotos = UserDefaults.standard.object(forKey: "importToPhotos") as? Bool ?? true
            if importToPhotos {
                let paths = photosToUpload.map { $0.filePath }
                let semaphore = DispatchSemaphore(value: 0)
                PhotosImporter.requestAccessIfNeeded { granted in
                    if granted { PhotosImporter.importFiles(paths) }
                    semaphore.signal()
                }
                semaphore.wait()
            }

            // Build the batch — every photo + the updated data.json — and ship in one commit
            // via the Git Data API. The old per-file Contents API loop fired N commits and tripped
            // the GitHub Pages legacy builder.
            var filesToUpload: [(path: String, content: Data)] = []
            for photo in photosToUpload {
                guard let fileData = fm.contents(atPath: photo.filePath) else { continue }
                filesToUpload.append((path: "docs/media/\(photo.filename)", content: fileData))

                let ext = (photo.filename as NSString).pathExtension.lowercased()
                let mediaType = (ext == "mp4") ? "video" : "photo"
                let attrs = try? fm.attributesOfItem(atPath: photo.filePath)
                let created = (attrs?[.creationDate] as? Date) ?? Date()
                newEntries.append([
                    "type": mediaType,
                    "filename": photo.filename,
                    "url": "media/\(photo.filename)",
                    "timestamp": isoFormatter.string(from: created),
                ])
            }

            if !filesToUpload.isEmpty {
                var existingEntries: [[String: String]] = []
                if let data = api.downloadFile(owner: username, repo: Config.repoName, path: "docs/data.json"),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                    existingEntries = json
                }
                let existingURLs = Set(existingEntries.compactMap { $0["url"] })
                let uniqueNew = newEntries.filter { !existingURLs.contains($0["url"] ?? "") }
                let mergedEntries = existingEntries + uniqueNew
                if let jsonData = try? JSONSerialization.data(withJSONObject: mergedEntries, options: [.prettyPrinted, .sortedKeys]) {
                    filesToUpload.append((path: "docs/data.json", content: jsonData))
                }

                do {
                    _ = try api.uploadFilesAsOneCommit(
                        owner: username,
                        repo: Config.repoName,
                        branch: "main",
                        files: filesToUpload,
                        message: "Add \(newEntries.count) media (review)"
                    )
                    uploadCount = newEntries.count
                } catch {
                    print("[Review] Batched upload failed: \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                self?.isSaving = false
                self?.saveMessage = "Uploaded \(uploadCount) photo(s) to gallery."
            }
        }
    }
}

// MARK: - ReviewView

struct ReviewView: View {
    @ObservedObject var viewModel: ReviewViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(viewModel.photos.count) photos")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
                if let msg = viewModel.saveMessage {
                    Text(msg)
                        .font(.callout)
                        .foregroundColor(.green)
                }
                Button("Apply Changes") {
                    viewModel.applyChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSaving || !viewModel.hasChanges)

                Button("Upload to Gallery") {
                    viewModel.uploadAll()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSaving)
            }
            .padding(12)

            if viewModel.isSaving {
                ProgressView("Saving...")
                    .padding()
            }

            // Photo Grid — using VStack+HStack instead of LazyVGrid to fix hit-testing
            ScrollView {
                let cols = 4
                let rows = stride(from: 0, to: viewModel.photos.count, by: cols)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows), id: \.self) { rowStart in
                        HStack(spacing: 8) {
                            ForEach(viewModel.photos[rowStart..<min(rowStart + cols, viewModel.photos.count)]) { photo in
                                PhotoTile(photo: photo)
                            }
                            if viewModel.photos.count - rowStart < cols {
                                Spacer()
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct PhotoTile: View {
    @ObservedObject var photo: ReviewPhoto

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let image = photo.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 140, height: 105)
                        .clipped()
                        .rotationEffect(.degrees(Double(photo.rotation)))
                        .allowsHitTesting(false)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 140, height: 105)
                }

                if photo.markedForDeletion {
                    Rectangle()
                        .fill(Color.red.opacity(0.4))
                        .frame(width: 140, height: 105)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }

            }
            .frame(width: 140, height: 105)
            .clipped()
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(photo.markedForDeletion ? Color.red : (photo.rotation != 0 ? Color.orange : Color.clear), lineWidth: 2)
            )

            // Buttons row using segmented style for reliable hit testing
            HStack(spacing: 0) {
                Text(photo.markedForDeletion ? "Undo" : "Delete")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(photo.markedForDeletion ? .gray : .red)
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(3)
                    .onTapGesture { photo.markedForDeletion.toggle() }

                if !photo.markedForDeletion {
                    Text("Rotate")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(3)
                        .onTapGesture { photo.rotate90() }
                }
            }
            .frame(width: 140)

            Text(photo.filename)
                .font(.system(size: 9))
                .foregroundColor(photo.markedForDeletion ? .red : .secondary)
                .lineLimit(1)
                .strikethrough(photo.markedForDeletion)

            if photo.rotation != 0 && !photo.markedForDeletion {
                Text("\(photo.rotation)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Window Controller

class ReviewWindowController {
    private var window: NSWindow?

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = ReviewViewModel()
        let view = ReviewView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: view)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 550),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Review Photos"
        w.contentView = hostingView
        w.contentMinSize = NSSize(width: 400, height: 350)
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}

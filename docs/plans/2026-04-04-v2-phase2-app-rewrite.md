# Charmera v2 Phase 2: Mac App Rewrite (GitHub Integration)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the Charmera Mac app to use GitHub for storage/hosting instead of Vercel, add a setup wizard with GitHub OAuth, photo management window, and login item support.

**Architecture:** Swift menu bar app using AppKit/SwiftUI. GitHub OAuth via custom URL scheme (`charmera://`) + auth proxy. GitHub REST API for repo creation, file upload, Pages setup. Keychain for token storage. SMAppService for login item. Bundled compressed ffmpeg for video conversion.

**Tech Stack:** Swift 6 (language mode v5), AppKit, SwiftUI, Security framework (Keychain), Vision framework, SMAppService

**Prereqs:** Phase 1 must be complete (auth proxy deployed, template files exist in `template/` directory).

---

## File Structure

```
charmera/app/
├── Package.swift
└── Charmera/
    ├── main.swift                  # Entry point
    ├── AppDelegate.swift           # Menu bar, URL scheme handler, app lifecycle
    ├── Config.swift                # Constants (GitHub client ID, auth proxy URL)
    ├── KeychainHelper.swift        # Save/load GitHub token from macOS Keychain
    ├── SetupWindow.swift           # SwiftUI first-launch setup wizard
    ├── GitHubAPI.swift             # GitHub REST API — create repo, upload files, enable Pages
    ├── Importer.swift              # Import pipeline — camera to local to GitHub
    ├── OrientationDetector.swift   # Vision framework orientation detection (unchanged)
    ├── PhotosImporter.swift        # AppleScript Photos.app import (unchanged)
    ├── FFmpegManager.swift         # Decompress + manage bundled ffmpeg
    ├── ManageWindow.swift          # SwiftUI photo management window (rotate, delete)
    └── PreferencesWindow.swift     # SwiftUI preferences (login item toggle, gallery URL)
```

---

### Task 1: Config + Keychain Helper

**Files:**
- Modify: `charmera/app/Charmera/Config.swift`
- Create: `charmera/app/Charmera/KeychainHelper.swift`

- [ ] **Step 1: Rewrite Config.swift for GitHub**

Replace `app/Charmera/Config.swift`:

```swift
import Foundation

enum Config {
    static let cameraVolumePath = "/Volumes/Charmera/DCIM"

    static let localBackupRoot: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Pictures/Charmera"
    }()

    static let hashFilePath: String = {
        return "\(localBackupRoot)/.imported-hashes"
    }()

    static let appSupportDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/Library/Application Support/Charmera"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    // GitHub OAuth
    static let githubClientID = "REPLACE_WITH_CLIENT_ID"
    static let authProxyURL = "https://charmera-auth.vercel.app/api/github"
    static let githubCallbackScheme = "charmera"

    // GitHub repo
    static let repoName = "charmera"
}
```

- [ ] **Step 2: Create KeychainHelper.swift**

Create `app/Charmera/KeychainHelper.swift`:

```swift
import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.charmera.app"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Convenience
    static var githubToken: String? {
        get { load(key: "github_token") }
        set {
            if let value = newValue { save(key: "github_token", value: value) }
            else { delete(key: "github_token") }
        }
    }

    static var githubUsername: String? {
        get { load(key: "github_username") }
        set {
            if let value = newValue { save(key: "github_username", value: value) }
            else { delete(key: "github_username") }
        }
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/timcox/tim-os/charmera/app && swift build 2>&1
```

Expected: Compiles (will have unused warnings, that's fine).

- [ ] **Step 4: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git add app/Charmera/Config.swift app/Charmera/KeychainHelper.swift
git commit -m "feat: Config for GitHub + Keychain token storage"
```

---

### Task 2: GitHub API Client

**Files:**
- Create: `charmera/app/Charmera/GitHubAPI.swift`

- [ ] **Step 1: Create GitHubAPI.swift**

Create `app/Charmera/GitHubAPI.swift`:

```swift
import Foundation

enum GitHubAPIError: Error, LocalizedError {
    case noToken
    case requestFailed(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .noToken: return "No GitHub token"
        case .requestFailed(let msg): return "GitHub API: \(msg)"
        case .decodingFailed: return "Failed to decode GitHub response"
        }
    }
}

struct GitHubAPI {
    let token: String

    private func request(_ method: String, path: String, body: [String: Any]? = nil) -> (Data?, HTTPURLResponse?) {
        guard let url = URL(string: "https://api.github.com\(path)") else { return (nil, nil) }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        var responseData: Data?
        var httpResponse: HTTPURLResponse?
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: req) { data, response, _ in
            responseData = data
            httpResponse = response as? HTTPURLResponse
            semaphore.signal()
        }.resume()
        semaphore.wait()

        return (responseData, httpResponse)
    }

    // MARK: - User

    func getUsername() throws -> String {
        let (data, response) = request("GET", path: "/user")
        guard let response, response.statusCode == 200,
              let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String else {
            throw GitHubAPIError.requestFailed("Failed to get username")
        }
        return login
    }

    // MARK: - Repo

    func createRepo(name: String) throws {
        let (data, response) = request("POST", path: "/user/repos", body: [
            "name": name,
            "description": "Photos from my Kodak Charmera keychain camera",
            "private": false,
            "auto_init": false,
        ])

        // 201 = created, 422 = already exists (fine)
        guard let response else { throw GitHubAPIError.requestFailed("No response") }
        if response.statusCode == 422 {
            print("[GitHubAPI] Repo already exists")
            return
        }
        guard response.statusCode == 201 else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
            throw GitHubAPIError.requestFailed("Create repo failed (\(response.statusCode)): \(body)")
        }
    }

    // MARK: - Files

    func uploadFile(owner: String, repo: String, path: String, content: Data, message: String, sha: String? = nil) throws -> String {
        let base64 = content.base64EncodedString()
        var body: [String: Any] = [
            "message": message,
            "content": base64,
        ]
        if let sha = sha { body["sha"] = sha }

        let (data, response) = request("PUT", path: "/repos/\(owner)/\(repo)/contents/\(path)", body: body)
        guard let response, (200...201).contains(response.statusCode),
              let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentObj = json["content"] as? [String: Any],
              let fileSha = contentObj["sha"] as? String else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
            throw GitHubAPIError.requestFailed("Upload \(path) failed: \(body)")
        }
        return fileSha
    }

    func deleteFile(owner: String, repo: String, path: String, sha: String, message: String) throws {
        let (data, response) = request("DELETE", path: "/repos/\(owner)/\(repo)/contents/\(path)", body: [
            "message": message,
            "sha": sha,
        ])
        guard let response, response.statusCode == 200 else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
            throw GitHubAPIError.requestFailed("Delete \(path) failed: \(body)")
        }
    }

    func getFileSHA(owner: String, repo: String, path: String) -> String? {
        let (data, response) = request("GET", path: "/repos/\(owner)/\(repo)/contents/\(path)")
        guard let response, response.statusCode == 200,
              let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = json["sha"] as? String else {
            return nil
        }
        return sha
    }

    // MARK: - Pages

    func enablePages(owner: String, repo: String) throws {
        let (data, response) = request("POST", path: "/repos/\(owner)/\(repo)/pages", body: [
            "source": ["branch": "main", "path": "/docs"]
        ])
        // 201 = created, 409 = already enabled
        guard let response, response.statusCode == 201 || response.statusCode == 409 else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
            throw GitHubAPIError.requestFailed("Enable Pages failed: \(body)")
        }
    }

    // MARK: - Template Push

    func pushTemplate(owner: String, repo: String, templateDir: String) throws {
        let fm = FileManager.default
        let docsDir = "\(templateDir)/docs"
        let readmePath = "\(templateDir)/README.md"

        // Push README.md
        if let readmeData = fm.contents(atPath: readmePath) {
            _ = try uploadFile(owner: owner, repo: repo, path: "README.md", content: readmeData, message: "Initial Charmera setup")
        }

        // Push docs/
        if let files = try? fm.contentsOfDirectory(atPath: docsDir) {
            for file in files {
                let filePath = "\(docsDir)/\(file)"
                if let fileData = fm.contents(atPath: filePath) {
                    _ = try uploadFile(owner: owner, repo: repo, path: "docs/\(file)", content: fileData, message: "Add \(file)")
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd /Users/timcox/tim-os/charmera/app && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git add app/Charmera/GitHubAPI.swift
git commit -m "feat: GitHub API client — repo, files, Pages"
```

---

### Task 3: Setup Window (SwiftUI)

**Files:**
- Create: `charmera/app/Charmera/SetupWindow.swift`
- Modify: `charmera/app/Charmera/AppDelegate.swift`

- [ ] **Step 1: Create SetupWindow.swift**

Create `app/Charmera/SetupWindow.swift`:

```swift
import SwiftUI
import ServiceManagement

struct SetupView: View {
    @State private var status: SetupStatus = .idle
    @State private var galleryURL: String = ""
    @State private var startAtLogin: Bool = true
    @State private var errorMessage: String?

    enum SetupStatus {
        case idle, waitingForAuth, provisioning, done, error
    }

    var body: some View {
        VStack(spacing: 0) {
            // Kodak header
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.894, green: 0.0, blue: 0.169))
                        .frame(width: 32, height: 29)
                    Text("K")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(red: 1.0, green: 0.718, blue: 0.0))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("KODAK")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(Color(red: 0.894, green: 0.0, blue: 0.169))
                    Text("Charmera")
                        .font(.system(size: 11, weight: .medium))
                        .italic()
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(red: 1.0, green: 0.718, blue: 0.0))

            // Rainbow stripe
            HStack(spacing: 0) {
                Color(red: 0.894, green: 0.0, blue: 0.169)
                Color(red: 0.91, green: 0.365, blue: 0.0)
                Color(red: 0.961, green: 0.651, blue: 0.137)
                Color(red: 1.0, green: 0.718, blue: 0.0)
                Color(red: 0.478, green: 0.714, blue: 0.282)
                Color(red: 0.0, green: 0.639, blue: 0.878)
            }
            .frame(height: 4)

            // Content
            VStack(spacing: 20) {
                switch status {
                case .idle:
                    Text("Import photos from your Kodak Charmera\nto your own gallery website.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.top, 20)

                    Button(action: startAuth) {
                        HStack {
                            Image(systemName: "person.crop.circle")
                            Text("Sign in with GitHub")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.black)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                case .waitingForAuth:
                    ProgressView()
                        .padding(.top, 20)
                    Text("Waiting for GitHub authorization...")
                        .foregroundColor(.secondary)

                case .provisioning:
                    ProgressView()
                        .padding(.top, 20)
                    Text("Setting up your gallery...")
                        .foregroundColor(.secondary)

                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                        .padding(.top, 20)
                    Text("Your gallery is ready!")
                        .font(.system(size: 16, weight: .semibold))
                    Text(galleryURL)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    Toggle("Start Charmera at login", isOn: $startAtLogin)
                        .onChange(of: startAtLogin) { _, newValue in
                            if newValue {
                                try? SMAppService.mainApp.register()
                            } else {
                                try? SMAppService.mainApp.unregister()
                            }
                        }
                        .padding(.horizontal)

                    Button("Done") {
                        NSApp.keyWindow?.close()
                    }
                    .keyboardShortcut(.defaultAction)

                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                        .padding(.top, 20)
                    Text(errorMessage ?? "Something went wrong")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again", action: startAuth)
                }
            }
            .padding(24)
        }
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func startAuth() {
        status = .waitingForAuth
        let urlStr = "https://github.com/login/oauth/authorize?client_id=\(Config.githubClientID)&scope=repo&redirect_uri=charmera://callback"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    func handleCallback(code: String) {
        status = .provisioning

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 1. Exchange code for token via auth proxy
                let token = try exchangeCode(code)
                KeychainHelper.githubToken = token

                // 2. Get username
                let api = GitHubAPI(token: token)
                let username = try api.getUsername()
                KeychainHelper.githubUsername = username

                // 3. Create repo
                try api.createRepo(name: Config.repoName)

                // 4. Push template files
                let templateDir = Bundle.main.resourcePath.map { "\($0)/template" }
                    ?? "\(FileManager.default.currentDirectoryPath)/template"
                try api.pushTemplate(owner: username, repo: Config.repoName, templateDir: templateDir)

                // 5. Enable GitHub Pages
                try api.enablePages(owner: username, repo: Config.repoName)

                let url = "https://\(username).github.io/\(Config.repoName)"

                DispatchQueue.main.async {
                    self.galleryURL = url
                    self.status = .done

                    // Register login item by default
                    try? SMAppService.mainApp.register()
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.status = .error
                }
            }
        }
    }

    private func exchangeCode(_ code: String) throws -> String {
        guard let url = URL(string: Config.authProxyURL) else {
            throw GitHubAPIError.requestFailed("Invalid auth proxy URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

        var result: String?
        var error: Error?
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: req) { data, _, err in
            defer { semaphore.signal() }
            if let err { error = err; return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                error = GitHubAPIError.requestFailed("No access_token in response")
                return
            }
            result = token
        }.resume()
        semaphore.wait()

        if let error { throw error }
        guard let token = result else { throw GitHubAPIError.requestFailed("No token") }
        return token
    }
}
```

- [ ] **Step 2: Rewrite AppDelegate.swift with URL scheme handler + setup window**

Replace `app/Charmera/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var isImporting = false
    private var setupWindow: NSWindow?
    private var setupView: SetupView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        updateIcon()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }

        // Show setup if no token
        if KeychainHelper.githubToken == nil {
            showSetupWindow()
        }
    }

    // MARK: - URL Scheme Handler

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == Config.githubCallbackScheme,
                  url.host == "callback",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                continue
            }
            setupView?.handleCallback(code: code)
        }
    }

    // MARK: - Setup Window

    private func showSetupWindow() {
        let view = SetupView()
        setupView = view

        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Charmera Setup"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupWindow = window
    }

    // MARK: - Menu Bar

    private var isCameraConnected: Bool {
        FileManager.default.fileExists(atPath: Config.cameraVolumePath)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let color: NSColor
        if isImporting {
            color = .systemBlue
        } else if isCameraConnected {
            color = NSColor(red: 1.0, green: 0.718, blue: 0.0, alpha: 1.0)
        } else {
            color = .gray
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
        ]
        button.attributedTitle = NSAttributedString(string: "K", attributes: attrs)
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        // Left click — import
        guard !isImporting else { return }
        guard KeychainHelper.githubToken != nil else {
            showSetupWindow()
            return
        }
        guard isCameraConnected else {
            showNotification(title: "Charmera", body: "No camera detected. Connect the Kodak Charmera and try again.")
            return
        }

        isImporting = true
        updateIcon()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let importer = Importer()
            let result = importer.run()

            DispatchQueue.main.async {
                self?.isImporting = false
                self?.updateIcon()

                switch result {
                case .success(let counts):
                    self?.showNotification(
                        title: "Charmera Import Complete",
                        body: "\(counts.photos) photo(s) and \(counts.videos) video(s) imported."
                    )
                case .failure(let error):
                    self?.showNotification(
                        title: "Charmera Import Failed",
                        body: error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()

        if let username = KeychainHelper.githubUsername {
            let galleryItem = NSMenuItem(title: "Open Gallery", action: #selector(openGallery), keyEquivalent: "")
            galleryItem.target = self
            menu.addItem(galleryItem)
        }

        let importItem = NSMenuItem(title: "Import from Camera", action: #selector(statusItemClicked), keyEquivalent: "")
        importItem.target = self
        importItem.isEnabled = isCameraConnected && !isImporting
        menu.addItem(importItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Charmera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openGallery() {
        if let username = KeychainHelper.githubUsername,
           let url = URL(string: "https://\(username).github.io/\(Config.repoName)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showPreferences() {
        // TODO: implement in Task 6
    }

    // MARK: - Notifications

    private func showNotification(title: String, body: String) {
        let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let safeBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", "display notification \"\(safeBody)\" with title \"\(safeTitle)\""]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/timcox/tim-os/charmera/app && swift build 2>&1
```

- [ ] **Step 4: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git add app/Charmera/AppDelegate.swift app/Charmera/SetupWindow.swift
git commit -m "feat: setup wizard with GitHub OAuth + right-click context menu"
```

---

### Task 4: Rewrite Importer for GitHub

**Files:**
- Modify: `charmera/app/Charmera/Importer.swift`
- Delete: `charmera/app/Charmera/BlobUploader.swift`

- [ ] **Step 1: Rewrite Importer.swift to upload to GitHub instead of Vercel Blob**

The import pipeline stays the same for steps 1-7 (discover, hash, copy, orient, convert, Photos.app) but replaces Vercel Blob upload + API POST with GitHub Contents API uploads + data.json update.

Key changes:
- Remove all Vercel Blob references
- Upload files via `GitHubAPI.uploadFile()` to `docs/media/`
- Read existing `docs/data.json`, append new entries, upload updated version
- Use `GitHubAPI.getFileSHA()` to get the current SHA of `data.json` before updating

Replace the upload section (steps 7-10) in Importer.swift with GitHub-based upload logic. Keep steps 1-6 (discover, hash, copy, orient, convert, Photos.app) and steps 9-10 (save hashes, delete from camera) unchanged.

The new upload section:

```swift
        // 7. Upload to GitHub repo
        guard let token = KeychainHelper.githubToken,
              let username = KeychainHelper.githubUsername else {
            throw NSError(domain: "Charmera", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Not signed in to GitHub"
            ])
        }

        let api = GitHubAPI(token: token)
        let repo = Config.repoName

        var newEntries: [[String: Any]] = []

        for item in allUploads {
            let fileURL = URL(fileURLWithPath: item.path)
            let filename = fileURL.lastPathComponent
            let fileData = try Data(contentsOf: fileURL)
            let attrs = try? fm.attributesOfItem(atPath: item.path)
            let created = (attrs?[.creationDate] as? Date) ?? Date()

            print("[Importer] Uploading \(filename) to GitHub...")
            _ = try api.uploadFile(
                owner: username,
                repo: repo,
                path: "docs/media/\(filename)",
                content: fileData,
                message: "Add \(filename)"
            )

            newEntries.append([
                "filename": filename,
                "type": item.type,
                "timestamp": isoFormatter.string(from: created),
                "rotation": 0,
            ])
        }

        // 8. Update data.json
        if !newEntries.isEmpty {
            var existing: [[String: Any]] = []
            let dataSHA = api.getFileSHA(owner: username, repo: repo, path: "docs/data.json")

            if let dataSHA = dataSHA {
                // Download existing data.json
                let (data, _) = api.downloadFile(owner: username, repo: repo, path: "docs/data.json")
                if let data, let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    existing = parsed
                }
            }

            existing.append(contentsOf: newEntries)
            let updatedData = try JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted)

            _ = try api.uploadFile(
                owner: username,
                repo: repo,
                path: "docs/data.json",
                content: updatedData,
                message: "Import \(newEntries.count) new photos",
                sha: dataSHA
            )
        }
```

Note: we need to add a `downloadFile` method to GitHubAPI. Add this to GitHubAPI.swift:

```swift
    func downloadFile(owner: String, repo: String, path: String) -> (Data?, HTTPURLResponse?) {
        let (data, response) = request("GET", path: "/repos/\(owner)/\(repo)/contents/\(path)")
        guard let response, response.statusCode == 200,
              let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentStr = json["content"] as? String,
              let decoded = Data(base64Encoded: contentStr.replacingOccurrences(of: "\n", with: "")) else {
            return (nil, nil)
        }
        return (decoded, response)
    }
```

- [ ] **Step 2: Delete BlobUploader.swift**

```bash
rm /Users/timcox/tim-os/charmera/app/Charmera/BlobUploader.swift
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/timcox/tim-os/charmera/app && swift build 2>&1
```

Fix any compilation errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git add app/Charmera/Importer.swift app/Charmera/GitHubAPI.swift
git rm app/Charmera/BlobUploader.swift
git commit -m "feat: import pipeline uploads to GitHub instead of Vercel Blob"
```

---

### Task 5: FFmpeg Manager

**Files:**
- Create: `charmera/app/Charmera/FFmpegManager.swift`
- Modify: `charmera/app/Charmera/Importer.swift`

- [ ] **Step 1: Create FFmpegManager.swift**

Create `app/Charmera/FFmpegManager.swift`:

```swift
import Foundation

enum FFmpegManager {
    static let ffmpegPath: String = {
        return "\(Config.appSupportDir)/ffmpeg"
    }()

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: ffmpegPath)
    }

    /// Decompress bundled ffmpeg.xz on first use
    static func ensureAvailable() -> Bool {
        if isAvailable { return true }

        // Look for bundled compressed binary
        let bundledPath = Bundle.main.resourcePath.map { "\($0)/ffmpeg.xz" }
            ?? "\(FileManager.default.currentDirectoryPath)/ffmpeg.xz"

        guard FileManager.default.fileExists(atPath: bundledPath) else {
            // Fallback: check if system ffmpeg is available
            if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") {
                return true
            }
            print("[FFmpeg] No bundled or system ffmpeg found")
            return false
        }

        print("[FFmpeg] Decompressing bundled ffmpeg...")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xz")
        proc.arguments = ["-d", "-k", bundledPath, "-o", ffmpegPath]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        // xz -d doesn't support -o, use a different approach
        let decompressCmd = "xz -d -c '\(bundledPath)' > '\(ffmpegPath)' && chmod +x '\(ffmpegPath)'"
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-c", decompressCmd]
        shell.standardOutput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice

        do {
            try shell.run()
            shell.waitUntilExit()
            guard shell.terminationStatus == 0 else {
                print("[FFmpeg] Decompression failed with status \(shell.terminationStatus)")
                return false
            }
            print("[FFmpeg] Decompressed to \(ffmpegPath)")
            return true
        } catch {
            print("[FFmpeg] Decompression error: \(error)")
            return false
        }
    }

    static var resolvedPath: String {
        if FileManager.default.isExecutableFile(atPath: ffmpegPath) {
            return ffmpegPath
        }
        return "/opt/homebrew/bin/ffmpeg"
    }
}
```

- [ ] **Step 2: Update Importer.swift to use FFmpegManager**

In `convertAVItoMP4`, replace the hardcoded ffmpeg path:

```swift
    private func convertAVItoMP4(input: String, output: String) {
        guard FFmpegManager.ensureAvailable() else {
            print("[Importer] ffmpeg not available — skipping video conversion")
            return
        }
        print("[Importer] Converting \(input) to MP4")
        let command = "\(shellEscape(FFmpegManager.resolvedPath)) -i \(shellEscape(input)) -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 128k -movflags +faststart -y \(shellEscape(output)) 2>/dev/null"
        _ = runShell(command)
    }
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/timcox/tim-os/charmera/app && swift build 2>&1
```

- [ ] **Step 4: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git add app/Charmera/FFmpegManager.swift app/Charmera/Importer.swift
git commit -m "feat: FFmpeg manager — decompress bundled binary on first use"
```

---

### Task 6: Preferences Window

**Files:**
- Create: `charmera/app/Charmera/PreferencesWindow.swift`
- Modify: `charmera/app/Charmera/AppDelegate.swift`

- [ ] **Step 1: Create PreferencesWindow.swift**

Create `app/Charmera/PreferencesWindow.swift`:

```swift
import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @State private var startAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var galleryURL: String = {
        if let username = KeychainHelper.githubUsername {
            return "https://\(username).github.io/\(Config.repoName)"
        }
        return ""
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Charmera Preferences")
                .font(.headline)

            if !galleryURL.isEmpty {
                HStack {
                    Text("Gallery:")
                        .foregroundColor(.secondary)
                    Text(galleryURL)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Open") {
                        if let url = URL(string: galleryURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Toggle("Start at login", isOn: $startAtLogin)
                .onChange(of: startAtLogin) { _, newValue in
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }

            Divider()

            Button("Sign Out of GitHub") {
                KeychainHelper.githubToken = nil
                KeychainHelper.githubUsername = nil
                NSApp.keyWindow?.close()
            }
            .foregroundColor(.red)
        }
        .padding(24)
        .frame(width: 400)
    }
}
```

- [ ] **Step 2: Wire up showPreferences in AppDelegate**

Replace the `showPreferences` stub:

```swift
    @objc private func showPreferences() {
        let hostingView = NSHostingView(rootView: PreferencesView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Charmera Preferences"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/timcox/tim-os/charmera/app && swift build 2>&1
```

- [ ] **Step 4: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git add app/Charmera/PreferencesWindow.swift app/Charmera/AppDelegate.swift
git commit -m "feat: preferences window with login item toggle and sign out"
```

---

### Task 7: Build App Bundle + DMG

**Files:**
- Create: build script or manual steps

- [ ] **Step 1: Build release binary**

```bash
cd /Users/timcox/tim-os/charmera/app
swift build -c release
```

- [ ] **Step 2: Create .app bundle structure**

```bash
APP="/Users/timcox/tim-os/charmera/dist/Charmera.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/template/docs"

# Copy binary
cp .build/release/Charmera "$APP/Contents/MacOS/Charmera"

# Copy template files
cp -r /Users/timcox/tim-os/charmera/template/docs/* "$APP/Contents/Resources/template/docs/"
cp /Users/timcox/tim-os/charmera/template/README.md "$APP/Contents/Resources/template/"
```

- [ ] **Step 3: Create Info.plist**

Create `dist/Charmera.app/Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.charmera.app</string>
    <key>CFBundleName</key>
    <string>Charmera</string>
    <key>CFBundleDisplayName</key>
    <string>Charmera</string>
    <key>CFBundleExecutable</key>
    <string>Charmera</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.charmera.callback</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>charmera</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

`LSUIElement = true` makes it a menu bar-only app (no dock icon).

- [ ] **Step 4: Create DMG**

```bash
cd /Users/timcox/tim-os/charmera
hdiutil create -volname "Charmera" -srcfolder dist/Charmera.app -ov -format UDZO dist/Charmera.dmg
```

- [ ] **Step 5: Test the app bundle**

```bash
open dist/Charmera.app
```

Verify: setup window appears with "Sign in with GitHub" button, "K" appears in menu bar.

- [ ] **Step 6: Create GitHub Release**

```bash
cd /Users/timcox/tim-os/charmera
git add dist/ docs/
git commit -m "feat: Charmera v2.0.0 — app bundle + DMG"
git tag v2.0.0
git push origin main --tags
gh release create v2.0.0 dist/Charmera.dmg --title "Charmera v2.0.0" --notes "macOS menu bar app for Kodak Charmera camera. Sign in with GitHub, import photos, auto-publish to your own gallery."
```

---

### Task 8: Homebrew Formula

**Files:**
- Create: separate repo `timncox/homebrew-charmera`

- [ ] **Step 1: Create the tap repo**

```bash
gh repo create timncox/homebrew-charmera --public --description "Homebrew tap for Charmera"
```

- [ ] **Step 2: Create the formula**

Create a local file and push:

```ruby
class Charmera < Formula
  desc "Kodak Charmera camera import + photo gallery"
  homepage "https://github.com/timncox/charmera"
  url "https://github.com/timncox/charmera/releases/download/v2.0.0/Charmera.dmg"
  sha256 "REPLACE_WITH_SHA256"
  version "2.0.0"

  depends_on :macos

  def install
    prefix.install "Charmera.app"
  end

  def caveats
    <<~EOS
      Charmera.app has been installed to:
        #{prefix}/Charmera.app

      To start it:
        open #{prefix}/Charmera.app

      To add to login items, right-click the K icon → Preferences → Start at login
    EOS
  end
end
```

- [ ] **Step 3: Push and test**

```bash
brew tap timncox/charmera
brew install charmera
```

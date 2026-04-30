import Foundation

struct GitHubAPI {
    let token: String

    private let baseURL = "https://api.github.com"

    // MARK: - Public Methods

    func getUsername() throws -> String {
        let data = try request(method: "GET", path: "/user")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String else {
            throw GitHubError.unexpectedResponse("Could not parse username from /user")
        }
        return login
    }

    func createRepo(name: String) throws {
        let body: [String: Any] = [
            "name": name,
            "auto_init": true,
            "private": false,
        ]
        do {
            _ = try request(method: "POST", path: "/user/repos", body: body, allowedStatuses: [201])
            print("[GitHubAPI] Created repo: \(name)")
        } catch GitHubError.httpStatus(let code, _) where code == 422 {
            // 422 = already exists, that's fine
            print("[GitHubAPI] Repo \(name) already exists")
        }
    }

    @discardableResult
    func uploadFile(owner: String, repo: String, path: String, content: Data, message: String, sha: String? = nil) throws -> String {
        let base64 = content.base64EncodedString()
        var body: [String: Any] = [
            "message": message,
            "content": base64,
        ]
        if let sha = sha {
            body["sha"] = sha
        }

        let data = try request(method: "PUT", path: "/repos/\(owner)/\(repo)/contents/\(path)", body: body, allowedStatuses: [200, 201])

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentObj = json["content"] as? [String: Any],
              let newSHA = contentObj["sha"] as? String else {
            throw GitHubError.unexpectedResponse("Could not parse SHA from upload response")
        }
        return newSHA
    }

    /// Uploads multiple files as a single commit using the Git Data API.
    /// One commit means one Pages build, instead of N rapid-fire builds that overwhelm the legacy
    /// builder and cause cascading "Page build failed" errors.
    @discardableResult
    func uploadFilesAsOneCommit(
        owner: String,
        repo: String,
        branch: String,
        files: [(path: String, content: Data)],
        message: String
    ) throws -> String {
        guard !files.isEmpty else {
            throw GitHubError.unexpectedResponse("uploadFilesAsOneCommit called with no files")
        }

        // 1. Resolve current branch tip and its tree.
        let refData = try request(method: "GET", path: "/repos/\(owner)/\(repo)/git/ref/heads/\(branch)")
        guard let refJSON = try JSONSerialization.jsonObject(with: refData) as? [String: Any],
              let refObj = refJSON["object"] as? [String: Any],
              let parentSHA = refObj["sha"] as? String else {
            throw GitHubError.unexpectedResponse("Could not parse ref for \(branch)")
        }

        let commitData = try request(method: "GET", path: "/repos/\(owner)/\(repo)/git/commits/\(parentSHA)")
        guard let commitJSON = try JSONSerialization.jsonObject(with: commitData) as? [String: Any],
              let treeObj = commitJSON["tree"] as? [String: Any],
              let baseTreeSHA = treeObj["sha"] as? String else {
            throw GitHubError.unexpectedResponse("Could not parse base tree from commit \(parentSHA)")
        }

        // 2. Create a blob for each file.
        var treeEntries: [[String: Any]] = []
        treeEntries.reserveCapacity(files.count)
        for file in files {
            let blobBody: [String: Any] = [
                "content": file.content.base64EncodedString(),
                "encoding": "base64",
            ]
            let blobData = try request(method: "POST", path: "/repos/\(owner)/\(repo)/git/blobs", body: blobBody, allowedStatuses: [201])
            guard let blobJSON = try JSONSerialization.jsonObject(with: blobData) as? [String: Any],
                  let blobSHA = blobJSON["sha"] as? String else {
                throw GitHubError.unexpectedResponse("Could not parse blob SHA for \(file.path)")
            }
            treeEntries.append([
                "path": file.path,
                "mode": "100644",
                "type": "blob",
                "sha": blobSHA,
            ])
        }

        // 3. Build a new tree on top of the base tree.
        let treeBody: [String: Any] = [
            "base_tree": baseTreeSHA,
            "tree": treeEntries,
        ]
        let newTreeData = try request(method: "POST", path: "/repos/\(owner)/\(repo)/git/trees", body: treeBody, allowedStatuses: [201])
        guard let newTreeJSON = try JSONSerialization.jsonObject(with: newTreeData) as? [String: Any],
              let newTreeSHA = newTreeJSON["sha"] as? String else {
            throw GitHubError.unexpectedResponse("Could not parse new tree SHA")
        }

        // 4. Create the commit referencing that tree.
        let commitBody: [String: Any] = [
            "message": message,
            "tree": newTreeSHA,
            "parents": [parentSHA],
        ]
        let newCommitData = try request(method: "POST", path: "/repos/\(owner)/\(repo)/git/commits", body: commitBody, allowedStatuses: [201])
        guard let newCommitJSON = try JSONSerialization.jsonObject(with: newCommitData) as? [String: Any],
              let newCommitSHA = newCommitJSON["sha"] as? String else {
            throw GitHubError.unexpectedResponse("Could not parse new commit SHA")
        }

        // 5. Fast-forward the branch to the new commit.
        let updateRefBody: [String: Any] = ["sha": newCommitSHA, "force": false]
        _ = try request(method: "PATCH", path: "/repos/\(owner)/\(repo)/git/refs/heads/\(branch)", body: updateRefBody, allowedStatuses: [200])

        return newCommitSHA
    }

    func deleteFile(owner: String, repo: String, path: String, sha: String, message: String) throws {
        let body: [String: Any] = [
            "message": message,
            "sha": sha,
        ]
        _ = try request(method: "DELETE", path: "/repos/\(owner)/\(repo)/contents/\(path)", body: body, allowedStatuses: [200])
    }

    func getFileSHA(owner: String, repo: String, path: String) -> String? {
        do {
            let data = try request(method: "GET", path: "/repos/\(owner)/\(repo)/contents/\(path)")
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sha = json["sha"] as? String {
                return sha
            }
        } catch {
            // File doesn't exist or other error
        }
        return nil
    }

    func downloadFile(owner: String, repo: String, path: String) -> Data? {
        do {
            let data = try request(method: "GET", path: "/repos/\(owner)/\(repo)/contents/\(path)")
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? String {
                // GitHub returns base64 with newlines
                let cleaned = content.replacingOccurrences(of: "\n", with: "")
                return Data(base64Encoded: cleaned)
            }
        } catch {
            // File doesn't exist or other error
        }
        return nil
    }

    /// Returns the set of filenames in a repo directory, or nil on error.
    /// Note: GitHub Contents API caps directory listings at 1000 entries; gallery is well under.
    func listDirectoryFilenames(owner: String, repo: String, path: String) -> Set<String>? {
        do {
            let data = try request(method: "GET", path: "/repos/\(owner)/\(repo)/contents/\(path)")
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            return Set(arr.compactMap { $0["name"] as? String })
        } catch {
            return nil
        }
    }

    func enablePages(owner: String, repo: String) throws {
        let body: [String: Any] = [
            "source": [
                "branch": "main",
                "path": "/docs",
            ]
        ]
        do {
            _ = try request(method: "POST", path: "/repos/\(owner)/\(repo)/pages", body: body, allowedStatuses: [201])
            print("[GitHubAPI] Enabled GitHub Pages")
        } catch GitHubError.httpStatus(let code, _) where code == 409 {
            // 409 = already enabled
            print("[GitHubAPI] GitHub Pages already enabled")
        }
    }

    func pushTemplate(owner: String, repo: String, templateDir: String) throws {
        let fm = FileManager.default

        // Upload README.md if it exists
        let readmePath = "\(templateDir)/README.md"
        if let readmeData = fm.contents(atPath: readmePath) {
            let existingSHA = getFileSHA(owner: owner, repo: repo, path: "README.md")
            _ = try uploadFile(owner: owner, repo: repo, path: "README.md", content: readmeData, message: "Add README", sha: existingSHA)
        }

        // Upload all files in docs/
        let docsDir = "\(templateDir)/docs"
        if let docsContents = try? fm.contentsOfDirectory(atPath: docsDir) {
            for filename in docsContents {
                let filePath = "\(docsDir)/\(filename)"
                guard let fileData = fm.contents(atPath: filePath) else { continue }
                let repoPath = "docs/\(filename)"
                let existingSHA = getFileSHA(owner: owner, repo: repo, path: repoPath)
                _ = try uploadFile(owner: owner, repo: repo, path: repoPath, content: fileData, message: "Add \(filename)", sha: existingSHA)
                print("[GitHubAPI] Pushed template file: \(repoPath)")
            }
        }
    }

    // MARK: - Private

    private func request(method: String, path: String, body: [String: Any]? = nil, allowedStatuses: Set<Int>? = nil) throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw GitHubError.invalidURL(path)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        if let body = body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        var httpStatusCode: Int?

        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            defer { semaphore.signal() }
            responseData = data
            responseError = error
            httpStatusCode = (response as? HTTPURLResponse)?.statusCode
        }
        task.resume()
        semaphore.wait()

        if let error = responseError {
            throw GitHubError.network(error.localizedDescription)
        }

        let statusCode = httpStatusCode ?? 0
        let data = responseData ?? Data()

        if let allowed = allowedStatuses {
            guard allowed.contains(statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw GitHubError.httpStatus(statusCode, body)
            }
        } else {
            guard statusCode >= 200 && statusCode < 300 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw GitHubError.httpStatus(statusCode, body)
            }
        }

        return data
    }
}

enum GitHubError: Error, LocalizedError {
    case invalidURL(String)
    case network(String)
    case httpStatus(Int, String)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Invalid URL: \(path)"
        case .network(let msg):
            return "Network error: \(msg)"
        case .httpStatus(let code, let body):
            return "HTTP \(code): \(body)"
        case .unexpectedResponse(let msg):
            return msg
        }
    }
}

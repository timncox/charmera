import Foundation

public enum Config {
    public static let cameraMarkerFolders = ["DCIM", "SPIDCIM"]

    public static var cameraVolumePath: String? {
        let fm = FileManager.default
        guard let volumes = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return nil }
        for volume in volumes {
            let volumePath = "/Volumes/\(volume)"
            let hasAll = cameraMarkerFolders.allSatisfy {
                fm.fileExists(atPath: "\(volumePath)/\($0)")
            }
            if hasAll {
                return "\(volumePath)/DCIM"
            }
        }
        return nil
    }

    public static let localBackupRoot: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Pictures/Charmera"
    }()

    public static let hashFilePath: String = { "\(localBackupRoot)/.imported-hashes" }()

    public static let appSupportDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/Library/Application Support/Charmera"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    public static let githubClientID = "Ov23liHp3TaFjD42UIUc"
    public static let authProxyURL = "https://charmera-auth.vercel.app/api/github"
    public static let githubCallbackScheme = "charmera"
    public static let repoName = "charmera-gallery"
}

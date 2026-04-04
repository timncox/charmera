import Foundation

enum FFmpegManager {

    static let ffmpegPath: String = {
        return "\(Config.appSupportDir)/ffmpeg"
    }()

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: ffmpegPath)
    }

    /// Decompress bundled ffmpeg.xz from app resources, or fall back to Homebrew.
    static func ensureAvailable() {
        if isAvailable { return }

        // Try to decompress bundled ffmpeg.xz from app resources
        let bundle = Bundle.main
        if let xzPath = bundle.path(forResource: "ffmpeg", ofType: "xz") {
            print("[FFmpeg] Decompressing bundled ffmpeg.xz")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/xz")
            proc.arguments = ["-dk", xzPath]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()

            // xz -dk produces the file next to the .xz with the .xz stripped
            let decompressed = xzPath.replacingOccurrences(of: ".xz", with: "")
            if FileManager.default.fileExists(atPath: decompressed) {
                try? FileManager.default.moveItem(atPath: decompressed, toPath: ffmpegPath)
                // Make executable
                let chmod = Process()
                chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmod.arguments = ["+x", ffmpegPath]
                chmod.standardOutput = FileHandle.nullDevice
                chmod.standardError = FileHandle.nullDevice
                try? chmod.run()
                chmod.waitUntilExit()
            }
        }

        if isAvailable {
            print("[FFmpeg] Available at \(ffmpegPath)")
        } else {
            print("[FFmpeg] Bundled not available, will check Homebrew fallback")
        }
    }

    /// Returns whichever path has the executable — bundled or Homebrew fallback.
    static var resolvedPath: String {
        if isAvailable {
            return ffmpegPath
        }

        let homebrewPath = "/opt/homebrew/bin/ffmpeg"
        if FileManager.default.isExecutableFile(atPath: homebrewPath) {
            return homebrewPath
        }

        // Intel Mac fallback
        let usrLocalPath = "/usr/local/bin/ffmpeg"
        if FileManager.default.isExecutableFile(atPath: usrLocalPath) {
            return usrLocalPath
        }

        return ffmpegPath // Return default even if not available; caller handles failure
    }
}

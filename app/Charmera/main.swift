import AppKit
import CharmeraCore

// CLI mode: when invoked with --import-photos <path1> <path2> ..., import the given files
// into the user's Photos library via PhotoKit, print a JSON summary, and exit.
// This exists so charmera-mcp (which can't claim Photos.app TCC scope on its own) can
// delegate Photos imports to the bundle identity that already owns the auth.
if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--import-photos" {
    let paths = Array(CommandLine.arguments.dropFirst(2))
    if paths.isEmpty {
        FileHandle.standardError.write(Data("usage: Charmera --import-photos <path>...\n".utf8))
        exit(2)
    }

    let semaphore = DispatchSemaphore(value: 0)
    var granted = false
    PhotosImporter.requestAccessIfNeeded { ok in
        granted = ok
        semaphore.signal()
    }
    semaphore.wait()

    guard granted else {
        let json = #"{"imported":0,"failed":\#(paths.count),"reason":"Photos access denied"}"# + "\n"
        FileHandle.standardOutput.write(Data(json.utf8))
        exit(1)
    }

    let imported = PhotosImporter.importFiles(paths)
    let json = "{\"imported\":\(imported),\"requested\":\(paths.count)}\n"
    FileHandle.standardOutput.write(Data(json.utf8))
    exit(imported == paths.count ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// Standalone CLI: read JPG paths on stdin (one per line), emit "<path>\t<rotation>"
// for each. Uses the same Vision-based 4-orientation face voting logic as the app.
//
// Compile: swiftc fix-orientation.swift -o /tmp/fix-orientation
// Usage:   ls *.jpg | /tmp/fix-orientation

import Foundation
import Vision
import AppKit

func bestRotation(cgImage: CGImage) -> Int {
    // Strategy: face landmarks give us the face's roll angle in radians at the
    // native orientation. That's a continuous, unambiguous signal — if a face
    // exists, it tells us exactly how the image is rotated.
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let landmarks = VNDetectFaceLandmarksRequest()
    try? handler.perform([landmarks])
    if let faces = landmarks.results, !faces.isEmpty {
        // Prefer the largest face (bbox area) for the rotation call — it's the
        // most likely subject and yields the most reliable roll.
        let biggest = faces.max { ($0.boundingBox.width * $0.boundingBox.height) < ($1.boundingBox.width * $1.boundingBox.height) }
        if let face = biggest, let rollNumber = face.roll {
            let roll = CGFloat(truncating: rollNumber)
            let deg = roll * 180 / .pi
            if abs(deg) < 30 { return 0 }
            if deg > 60 && deg < 120 { return 90 }     // face tilted left in view → rotate 90° CW
            if deg < -60 && deg > -120 { return 270 }  // face tilted right in view → rotate 270° CW
            if abs(deg) > 150 { return 180 }
        }
    }

    // Fallback: if no face at the native orientation, face detectors may still
    // find faces when the image is mentally rotated. Vote over 4 orientations.
    let candidates: [(CGImagePropertyOrientation, Int)] = [
        (.up, 0), (.right, 270), (.down, 180), (.left, 90),
    ]
    var best: (rotation: Int, score: Float)? = nil
    for (orient, rot) in candidates {
        let h = VNImageRequestHandler(cgImage: cgImage, orientation: orient, options: [:])
        let req = VNDetectFaceRectanglesRequest()
        try? h.perform([req])
        guard let faces = req.results, !faces.isEmpty else { continue }
        let score = faces.reduce(Float(0)) { $0 + $1.confidence }
        if best == nil || score > best!.score { best = (rot, score) }
    }
    if let w = best, w.score >= 0.8 { return w.rotation }

    // Final fallback: horizon
    let h2 = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let horizonReq = VNDetectHorizonRequest()
    try? h2.perform([horizonReq])
    if let horiz = horizonReq.results?.first {
        let deg = horiz.angle * 180 / .pi
        if abs(deg) < 20 { return 0 }
        if deg > 70 && deg < 110 { return 270 }
        if deg < -70 && deg > -110 { return 90 }
        if abs(deg) > 160 { return 180 }
    }
    return 0
}

while let line = readLine() {
    let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else { continue }
    guard let image = NSImage(contentsOfFile: path),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("\(path)\t0")
        continue
    }
    print("\(path)\t\(bestRotation(cgImage: cgImage))")
    fflush(stdout)
}

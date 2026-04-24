import Foundation
import Vision
import AppKit

enum OrientationDetector {

    /// Clockwise rotation (0, 90, 180, 270) needed to make an image upright.
    static func detectRotation(imagePath: String) -> Int {
        guard let image = NSImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }

        if let r = rotationFromFaceRoll(cgImage: cgImage) {
            print("[Orientation] face-roll: \(imagePath) -> \(r)°")
            return r
        }
        if let r = rotationFromFaceVoting(cgImage: cgImage) {
            print("[Orientation] face-voting: \(imagePath) -> \(r)°")
            return r
        }
        if let r = rotationFromHorizon(cgImage: cgImage) {
            print("[Orientation] horizon: \(imagePath) -> \(r)°")
            return r
        }
        return 0
    }

    // Face landmarks at native orientation give a continuous roll angle — the
    // most precise signal when a face is present. We prefer the biggest face.
    private static func rotationFromFaceRoll(cgImage: CGImage) -> Int? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let req = VNDetectFaceLandmarksRequest()
        try? handler.perform([req])
        guard let faces = req.results, !faces.isEmpty else { return nil }

        let biggest = faces.max {
            ($0.boundingBox.width * $0.boundingBox.height)
            < ($1.boundingBox.width * $1.boundingBox.height)
        }
        guard let face = biggest, let rollNumber = face.roll else { return nil }

        let deg = CGFloat(truncating: rollNumber) * 180 / .pi
        if abs(deg) < 30 { return 0 }
        if deg > 60 && deg < 120 { return 90 }
        if deg < -60 && deg > -120 { return 270 }
        if abs(deg) > 150 { return 180 }
        return nil
    }

    // Fallback when landmarks find no face at .up: run face rectangles at four
    // orientations and keep the best by summed confidence.
    private static func rotationFromFaceVoting(cgImage: CGImage) -> Int? {
        let candidates: [(CGImagePropertyOrientation, Int)] = [
            (.up, 0), (.right, 270), (.down, 180), (.left, 90),
        ]
        var best: (rotation: Int, score: Float)? = nil
        for (orient, rot) in candidates {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orient, options: [:])
            let req = VNDetectFaceRectanglesRequest()
            try? handler.perform([req])
            guard let faces = req.results, !faces.isEmpty else { continue }
            let score = faces.reduce(Float(0)) { $0 + $1.confidence }
            if best == nil || score > best!.score { best = (rot, score) }
        }
        guard let w = best, w.score >= 0.8 else { return nil }
        return w.rotation
    }

    private static func rotationFromHorizon(cgImage: CGImage) -> Int? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let req = VNDetectHorizonRequest()
        try? handler.perform([req])
        guard let h = req.results?.first else { return nil }
        let deg = h.angle * 180 / .pi
        if abs(deg) < 20 { return 0 }
        if deg > 70 && deg < 110 { return 270 }
        if deg < -70 && deg > -110 { return 90 }
        if abs(deg) > 160 { return 180 }
        return nil
    }
}

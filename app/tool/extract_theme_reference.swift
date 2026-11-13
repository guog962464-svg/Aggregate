// swift -suppress-warnings tool/extract_theme_reference.swift input.mp4 output
// Sequential decoding preserves presentation timestamps. Image-generator seek
// tolerances must not be used to reconstruct an animation's frame timing.
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fatalError("Expected an input movie path and an output directory")
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let asset = AVURLAsset(url: source)
let tracks = try await asset.loadTracks(withMediaType: .video)
guard let track = tracks.first else { fatalError("No video track") }
let duration = try await asset.load(.duration)
let naturalSize = try await track.load(.naturalSize)
let rate = try await track.load(.nominalFrameRate)
let transform = try await track.load(.preferredTransform)
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
])
reader.add(output)
guard reader.startReading() else { throw reader.error! }
let context = CIContext(options: [.cacheIntermediates: false])
var frames: [[String: Any]] = []
while let sample = output.copyNextSampleBuffer() {
    guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    let presentation = CMSampleBufferGetPresentationTimeStamp(sample).seconds
    let length = CMSampleBufferGetDuration(sample).seconds
    let image = CIImage(cvPixelBuffer: buffer)
    guard let pixels = context.createCGImage(image, from: image.extent) else {
        fatalError("Cannot decode frame \(frames.count)")
    }
    let filename = String(format: "frame_%04d.png", frames.count)
    let url = directory.appendingPathComponent(filename)
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, pixels, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
    frames.append([
        "index": frames.count, "pts": presentation,
        "duration": length.isFinite ? length : 0, "file": filename,
    ])
}
if reader.status == .failed { throw reader.error! }
let metadata: [String: Any] = [
    "duration": duration.seconds, "width": naturalSize.width,
    "height": naturalSize.height, "fps": rate,
    "transform": [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty],
    "frames": frames,
]
try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("frames.json"), options: .atomic)
print("Decoded \(frames.count) frames with their original presentation timestamps")

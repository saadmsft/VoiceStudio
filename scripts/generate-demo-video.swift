import AVFoundation
import AppKit
import CoreMedia
import CoreVideo
import Foundation

guard CommandLine.arguments.count >= 6 else {
    fputs("Usage: swift generate-demo-video.swift <frameRaw.png> <raw.m4a> <frameStudio.png> <studio.m4a> <out.mp4>\n", stderr)
    exit(1)
}

let rawImgPath = CommandLine.arguments[1]
let rawAudioPath = CommandLine.arguments[2]
let studioImgPath = CommandLine.arguments[3]
let studioAudioPath = CommandLine.arguments[4]
let outMp4Path = CommandLine.arguments[5]

func loadPixelBuffer(from path: String, width: Int, height: Int) -> CVPixelBuffer? {
    guard let nsImage = NSImage(contentsOfFile: path),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pb)
    guard let buffer = pb else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    ) else { return nil }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
}

let rawAsset = AVURLAsset(url: URL(fileURLWithPath: rawAudioPath))
let studioAsset = AVURLAsset(url: URL(fileURLWithPath: studioAudioPath))
let rawDur = CMTimeGetSeconds(rawAsset.duration)
let studioDur = CMTimeGetSeconds(studioAsset.duration)

let width = 1280
let height = 720
let fps: Int32 = 10
let tempSilentVideo = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("voicestudio-silent-\(UUID().uuidString).mp4")
try? FileManager.default.removeItem(at: tempSilentVideo)

let writer = try AVAssetWriter(outputURL: tempSilentVideo, fileType: .mp4)
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height
]
let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vInput, sourcePixelBufferAttributes: nil)
writer.add(vInput)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

guard let rawPB = loadPixelBuffer(from: rawImgPath, width: width, height: height),
      let studioPB = loadPixelBuffer(from: studioImgPath, width: width, height: height) else {
    fputs("Failed to load video frame PNGs\n", stderr)
    exit(1)
}

let rawFrames = max(1, Int(ceil(rawDur * Double(fps))))
let totalFrames = max(rawFrames + 1, Int(ceil((rawDur + studioDur) * Double(fps))))

for f in 0...totalFrames {
    while !vInput.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.005)
    }
    let t = CMTime(value: CMTimeValue(f), timescale: fps)
    let pb = f < rawFrames ? rawPB : studioPB
    adaptor.append(pb, withPresentationTime: t)
}

vInput.markAsFinished()
let writeSem = DispatchSemaphore(value: 0)
writer.finishWriting { writeSem.signal() }
writeSem.wait()

// Combine video track + concatenated raw & studio audio tracks via AVMutableComposition
let comp = AVMutableComposition()
let vAsset = AVURLAsset(url: tempSilentVideo)
if let compVid = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
   let srcVid = vAsset.tracks(withMediaType: .video).first {
    try compVid.insertTimeRange(CMTimeRange(start: .zero, duration: vAsset.duration), of: srcVid, at: .zero)
}
if let compAud = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
   let srcRawAud = rawAsset.tracks(withMediaType: .audio).first,
   let srcStudioAud = studioAsset.tracks(withMediaType: .audio).first {
    try compAud.insertTimeRange(CMTimeRange(start: .zero, duration: rawAsset.duration), of: srcRawAud, at: .zero)
    try compAud.insertTimeRange(CMTimeRange(start: .zero, duration: studioAsset.duration), of: srcStudioAud, at: rawAsset.duration)
}

let outURL = URL(fileURLWithPath: outMp4Path)
try? FileManager.default.removeItem(at: outURL)
guard let exporter = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
    fputs("Failed to create AVAssetExportSession\n", stderr)
    exit(1)
}
exporter.outputURL = outURL
exporter.outputFileType = .mp4
exporter.shouldOptimizeForNetworkUse = true

let expSem = DispatchSemaphore(value: 0)
exporter.exportAsynchronously { expSem.signal() }
expSem.wait()
try? FileManager.default.removeItem(at: tempSilentVideo)

if exporter.status == .completed {
    print("Created MP4 A/B Demo Video -> \(outMp4Path)")
} else {
    fputs("Export failed: \(String(describing: exporter.error))\n", stderr)
    exit(1)
}

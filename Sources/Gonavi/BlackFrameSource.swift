import AVFoundation
import GonaviCore

/// One reusable frame is stretched across empty regions; no duration-sized video allocation.
actor BlackFrameSource {
    static let shared = BlackFrameSource()
    private var pending: Task<URL, Error>?
    func url() async throws -> URL {
        if let pending { return try await pending.value }
        let task = Task<URL, Error> {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("gonavi-black-\(UUID().uuidString).mov")
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                                                                             AVVideoWidthKey: 320, AVVideoHeightKey: 180])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? ProjectError.invalid("Boş kare oluşturulamadı.") }
            writer.startSession(atSourceTime: .zero)
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? ProjectError.invalid("Boş kare yazılamadı.") }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
                throw ProjectError.invalid("Boş kare belleği ayrılamadı.")
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 0, CVPixelBufferGetDataSize(buffer))
                for y in 0..<180 { for x in 0..<320 { base.storeBytes(of: UInt8(255), toByteOffset: y * CVPixelBufferGetBytesPerRow(buffer) + x * 4, as: UInt8.self) } }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: .zero) else { throw writer.error ?? ProjectError.invalid("Boş kare eklenemedi.") }
            writer.endSession(atSourceTime: CMTime(value: 1, timescale: 30)); input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? ProjectError.invalid("Boş kare tamamlanamadı.") }
            return url
        }
        pending = task
        do { return try await task.value } catch { pending = nil; throw error }
    }
}

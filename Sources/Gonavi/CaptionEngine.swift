import AVFoundation
import CryptoKit
import Foundation
import GonaviCore

enum CaptionModel: String, CaseIterable, Identifiable {
    case small, medium
    var id: String { rawValue }
    var title: String { self == .small ? "Dengeli · 190 MB" : "Daha yüksek doğruluk · 539 MB" }
    var detail: String { self == .small ? "Intel Mac için önerilen başlangıç. Daha az bellek kullanır." : "Zor konuşmalarda daha iyi sonuç verebilir. Intel’de daha uzun sürer." }
    var filename: String { self == .small ? "ggml-small-q5_1.bin" : "ggml-medium-q5_0.bin" }
    var bytes: Int64 { self == .small ? 190_085_487 : 539_212_467 }
    var sha256: String {
        self == .small ? "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
            : "19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f"
    }
    var url: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/\(filename)")!
    }
    var localURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gonavi/Models").appendingPathComponent(filename)
    }
    var installed: Bool { FileManager.default.fileExists(atPath: localURL.path) }
}

private final class ModelDownloadObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let expected: Int64
    let report: @Sendable (Double) -> Void
    init(expected: Int64, report: @escaping @Sendable (Double) -> Void) { self.expected = expected; self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        report(min(1, Double(totalBytesWritten) / Double(expected)))
    }
}

enum CaptionEngine {
    typealias Report = @Sendable (String, Double?) -> Void

    static func verifyModel(_ url: URL, bytes: Int64, sha256: String) async throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == bytes else {
            throw ProjectError.invalid("Model dosyası eksik. Modeli yeniden indirin.")
        }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var digest = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation(); digest.update(data: data)
        }
        guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw ProjectError.invalid("Model doğrulanamadı. Modeli yeniden indirin.")
        }
    }

    static func ensureModel(_ model: CaptionModel, report: @escaping Report) async throws -> URL {
        if model.installed {
            report("Model doğrulanıyor…", nil)
            try await verifyModel(model.localURL, bytes: model.bytes, sha256: model.sha256)
            return model.localURL
        }
        report("Türkçe konuşma modeli indiriliyor…", 0)
        let observer = ModelDownloadObserver(expected: model.bytes) { report("Türkçe konuşma modeli indiriliyor…", $0) }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: model.url, delegate: observer)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProjectError.invalid("Model indirilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin.")
        }
        report("İndirilen model doğrulanıyor…", nil)
        try await verifyModel(temporary, bytes: model.bytes, sha256: model.sha256)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: model.localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temporary, to: model.localURL)
        return model.localURL
    }

    static var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/whisper-cli") }

    static func transcribe(project: Project, model: URL, language: String = "tr", style: CaptionStyle,
                           report: @escaping Report) async throws -> [Caption] {
        try project.validate()
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw ProjectError.invalid("Konuşma motoru bulunamadı. Gonavi’nin tam uygulama paketini kullanın.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Gonavi-Captions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var result: [Caption] = [], timeline = EditTime.zero
        for (index, clip) in project.clips.enumerated() {
            guard let source = project.sources.first(where: { $0.id == clip.sourceID }) else {
                throw ProjectError.invalid("Konuşma için kaynak video bulunamadı.")
            }
            let asset = AVURLAsset(url: try MediaEngine.resolve(source))
            var position = EditTime.zero
            // Bounded chunks keep the decoder's PCM buffer below 10 MB, even for long videos.
            while position < clip.duration {
                try Task.checkCancellation()
                let length = min(EditTime(seconds: 300), clip.duration - position)
                let progress = (timeline + position).seconds / max(1, project.duration.seconds)
                let label = "Klip \(index + 1)/\(project.clips.count) · \(Int((timeline + position).seconds)) / \(Int(project.duration.seconds)) sn"
                report("Ses hazırlanıyor · \(label)", progress)
                let wav = folder.appendingPathComponent("chunk.wav")
                let hasSound = try await extractAudio(asset: asset, start: clip.sourceStart + position, duration: length, to: wav)
                if hasSound {
                    report("Türkçe altyazı üretiliyor · \(label)", progress)
                    let prefix = folder.appendingPathComponent("transcript")
                    let json = prefix.appendingPathExtension("json")
                    try? FileManager.default.removeItem(at: json)
                    try await recognize(wav: wav, model: model, output: prefix, language: language)
                    let captions = try WhisperTranscript.captions(from: Data(contentsOf: json), offset: timeline + position,
                                                                  limit: length, style: style)
                    result.append(contentsOf: captions)
                }
                position = position + length
            }
            timeline = timeline + clip.duration
        }
        try Task.checkCancellation()
        report("Altyazılar hazır", 1)
        return result
    }

    static func recognize(wav: URL, model: URL, output: URL, language: String) async throws {
        var arguments = ["-m", model.path, "-f", wav.path, "-l", language, "-ojf", "-of", output.path,
                         "-t", String(min(8, max(1, ProcessInfo.processInfo.activeProcessorCount - 1))),
                         "-sow", "-ml", "42", "-sns"]
        #if arch(x86_64)
        arguments.append("-ng")
        #endif
        let process = CaptionProcess(executable: helperURL, arguments: arguments, log: output.appendingPathExtension("log"))
        try await withTaskCancellationHandler(operation: { try await process.run() }, onCancel: { process.cancel() })
    }

    /// Decode only the original video's audio, before music and volume effects.
    /// Pad using sample timestamps so tracks with delayed audio retain sync.
    static func extractAudio(asset: AVAsset, start: EditTime, duration: EditTime, to url: URL) async throws -> Bool {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return false }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ProjectError.invalid("Videonun sesi çözümlenemedi.") }
        reader.add(output); reader.timeRange = CMTimeRange(start: start.cm, duration: duration.cm)
        guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Ses okuma başlatılamadı.") }
        defer { reader.cancelReading() }
        let frames = Int((duration.seconds * 16000).rounded())
        let byteCount = frames * 2
        var header = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { header.append(contentsOf: $0) } }
        append(UInt32(36 + byteCount)); header.append(Data("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(16000)); append(UInt32(32000))
        append(UInt16(2)); append(UInt16(16)); header.append(Data("data".utf8)); append(UInt32(byteCount))
        try header.write(to: url)
        let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
        try file.seekToEnd()
        var written = 0, energy: Double = 0
        let zeros = Data(repeating: 0, count: 32_000)
        func pad(to target: Int) throws {
            while written < target {
                try Task.checkCancellation()
                let count = min(zeros.count, target - written)
                try file.write(contentsOf: zeros.prefix(count)); written += count
            }
        }
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let count = CMBlockBufferGetDataLength(block)
            var data = Data(count: count)
            let code = data.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: raw.baseAddress!)
            }
            guard code == kCMBlockBufferNoErr else { throw ProjectError.invalid("Ses örnekleri okunamadı.") }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard timestamp.isFinite else { throw ProjectError.invalid("Ses zaman kodu geçersiz.") }
            let destination = Int(((timestamp - start.seconds) * 16000).rounded()) * 2
            try pad(to: min(byteCount, max(0, destination)))
            let skip = max(0, written - destination)
            let available = min(count - min(count, skip), byteCount - written)
            if available > 0 {
                let slice = data.subdata(in: skip..<(skip + available))
                slice.withUnsafeBytes { raw in
                    for value in raw.bindMemory(to: Int16.self) {
                        let normalized = Double(Int16(littleEndian: value)) / 32768
                        energy += normalized * normalized
                    }
                }
                try file.write(contentsOf: slice); written += available
            }
        }
        guard reader.status == .completed else { throw reader.error ?? ProjectError.invalid("Ses okuma tamamlanamadı.") }
        try pad(to: byteCount)
        // Skip near-digital silence; this is not a general voice activity detector.
        return sqrt(energy / Double(max(1, frames))) > 0.0001
    }
}

private final class CaptionProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private let log: URL
    init(executable: URL, arguments: [String], log: URL) {
        process.executableURL = executable; process.arguments = arguments; self.log = log
    }
    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock(); defer { lock.unlock() }
            guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
            do {
                try Data().write(to: log)
                let handle = try FileHandle(forWritingTo: log)
                process.standardOutput = handle; process.standardError = handle
                process.terminationHandler = { [log] process in
                    try? handle.close()
                    if process.terminationStatus == 0 { continuation.resume() }
                    else {
                        let detail = (try? String(contentsOf: log, encoding: .utf8))?.suffix(1600) ?? ""
                        continuation.resume(throwing: ProjectError.invalid("Konuşma motoru tamamlanamadı (\(process.terminationStatus)).\n\(detail)"))
                    }
                }
                do { try process.run() }
                catch { try? handle.close(); process.terminationHandler = nil; throw error }
            } catch { continuation.resume(throwing: error) }
        }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if process.isRunning { process.terminate() }
    }
}

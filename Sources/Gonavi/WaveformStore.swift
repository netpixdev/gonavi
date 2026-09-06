import AVFoundation
import Combine
import CryptoKit
import Foundation
import GonaviCore

enum WaveformEntry: Sendable {
    case loading
    case ready(WaveformData)
    case noAudio
    case failed(String)
}

/// One background decoder at a time keeps importing a large media library from
/// spawning a PCM decoder for every file. Tokens reject results from old media.
@MainActor
final class WaveformStore: ObservableObject {
    @Published private(set) var entries: [UUID: WaveformEntry] = [:]
    private var sources: [UUID: MediaSource] = [:]
    private var generations: [UUID: UUID] = [:]
    private struct Work {
        let source: MediaSource
        let generation: UUID
        let bypassCache: Bool
    }
    private var pending: [Work] = []
    private var worker: Task<Void, Never>?
    private var activeTask: Task<WaveformEntry?, Never>?
    private var activeID: UUID?

    func load(_ media: [MediaSource]) {
        let ids = Set(media.map(\.id))
        for id in Set(sources.keys).subtracting(ids) {
            sources[id] = nil; entries[id] = nil; generations[id] = nil
            pending.removeAll { $0.source.id == id }
            if activeID == id { activeTask?.cancel() }
        }
        for source in media where sources[source.id] != source {
            sources[source.id] = source
            enqueue(source, bypassCache: false)
        }
        startWorker()
    }

    /// Call after relinking/replacing a file or to retry a failed decode.
    func invalidate(_ sourceID: UUID) {
        guard let source = sources[sourceID] else { return }
        enqueue(source, bypassCache: true)
        startWorker()
    }

    func cancelAll() {
        // Keep the worker alive until its cancelled decoder actually returns;
        // a later load can safely append work without overlapping decoders.
        activeTask?.cancel(); pending.removeAll()
        sources.removeAll(); generations.removeAll(); entries.removeAll()
    }

    private func enqueue(_ source: MediaSource, bypassCache: Bool) {
        let generation = UUID()
        generations[source.id] = generation; entries[source.id] = .loading
        pending.removeAll { $0.source.id == source.id }
        if activeID == source.id { activeTask?.cancel() }
        pending.append(Work(source: source, generation: generation, bypassCache: bypassCache))
    }

    private func startWorker() {
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in await self?.drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let item = pending.removeFirst()
            guard generations[item.source.id] == item.generation else { continue }
            activeID = item.source.id
            let task = Task.detached(priority: .utility) { () -> WaveformEntry? in
                do {
                    return try await WaveformDecoder.decode(item.source, useCache: !item.bypassCache)
                } catch is CancellationError {
                    return nil
                } catch {
                    if Task.isCancelled { return nil }
                    return .failed(error.localizedDescription)
                }
            }
            activeTask = task
            let result = await task.value
            if generations[item.source.id] == item.generation, let result {
                entries[item.source.id] = result
            }
            activeTask = nil; activeID = nil
        }
        worker = nil
    }

    deinit { worker?.cancel(); activeTask?.cancel() }
}

enum WaveformDecoder {
    private static let sampleRate = 16_000
    private static let cacheVersion = 2
    private static let maximumCacheFileSize = 192 * 1024 * 1024
    private static let cacheBudget = 256 * 1024 * 1024
    private struct CachedWaveform: Codable {
        let version: Int
        let waveform: WaveformData?
    }

    static func decode(_ source: MediaSource, useCache: Bool = true) async throws -> WaveformEntry {
        try Task.checkCancellation()
        let url = try MediaEngine.resolve(source).standardizedFileURL.resolvingSymlinksInPath()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let cacheURL = try cacheLocation(for: url, source: source)
        if useCache, let cached = readCache(cacheURL) {
            try Task.checkCancellation()
            return cached.waveform.map(WaveformEntry.ready) ?? .noAudio
        }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            try Task.checkCancellation()
            writeCache(CachedWaveform(version: cacheVersion, waveform: nil), to: cacheURL)
            return .noAudio
        }
        let duration = try await asset.load(.duration).seconds
        let descriptions = try await track.load(.formatDescriptions)
        let channels = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }.map(Int.init) ?? 1
        guard (1...32).contains(channels) else { throw ProjectError.invalid("Ses kanal sayısı desteklenmiyor.") }
        var accumulator = try AudioPeakAccumulator(duration: duration, sampleRate: sampleRate)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ProjectError.invalid("Ses dalga formu çözümlenemedi.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Ses okuma başlatılamadı.") }
        defer { reader.cancelReading() }
        while reader.status == .reading {
            try Task.checkCancellation()
            let readSample: Bool = try autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else { return false }
                guard let block = CMSampleBufferGetDataBuffer(sample) else { return true }
                let byteCount = CMBlockBufferGetDataLength(block)
                guard byteCount > 0 else { return true }
                guard byteCount % MemoryLayout<Float>.size == 0, byteCount <= 16 * 1024 * 1024 else {
                    throw ProjectError.invalid("Ses örnek boyutu geçersiz.")
                }
                // AVAssetReader may return a non-contiguous CMBlockBuffer.
                // Copy just this packet; never retain the whole decoded file.
                var samples = [Float](repeating: 0, count: byteCount / MemoryLayout<Float>.size)
                let code = samples.withUnsafeMutableBytes { raw in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: raw.baseAddress!)
                }
                guard code == kCMBlockBufferNoErr else { throw ProjectError.invalid("Ses örnekleri okunamadı.") }
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                try samples.withUnsafeBufferPointer { try accumulator.append($0, at: timestamp, channels: channels) }
                return true
            }
            if !readSample { break }
        }
        try Task.checkCancellation()
        guard reader.status == .completed else { throw reader.error ?? ProjectError.invalid("Ses okuma tamamlanamadı.") }
        let waveform = try accumulator.finish()
        try Task.checkCancellation()
        // A file may be replaced while decoding. Never cache its old samples
        // under the replacement's identity.
        if (try? cacheLocation(for: url, source: source)) == cacheURL {
            writeCache(CachedWaveform(version: cacheVersion, waveform: waveform), to: cacheURL)
        }
        return .ready(waveform)
    }

    private static func cacheLocation(for url: URL, source: MediaSource) throws -> URL {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let identity = "\(cacheVersion)\n\(url.path)\n\(size)\n\(modified)\n\(source.duration.ticks)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gonavi/Waveforms", isDirectory: true)
        return directory.appendingPathComponent(key).appendingPathExtension("plist")
    }

    private static func readCache(_ url: URL) -> CachedWaveform? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size > 0, size <= maximumCacheFileSize,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let cached = try? PropertyListDecoder().decode(CachedWaveform.self, from: data),
              cached.version == cacheVersion else { return nil }
        return cached
    }

    private static func writeCache(_ waveform: CachedWaveform, to url: URL) {
        guard !Task.isCancelled else { return }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        guard let data = try? encoder.encode(waveform), data.count <= maximumCacheFileSize, !Task.isCancelled else { return }
        let directory = url.deletingLastPathComponent(), manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            trimCache(in: directory)
        } catch { /* A cache is optional; a read-only/full disk must not hide a decoded waveform. */ }
    }

    private static func trimCache(in directory: URL) {
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        let files = urls.filter { $0.pathExtension == "plist" }.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = files.reduce(0) { $0 + $1.1 }
        for file in files where size > cacheBudget {
            if (try? manager.removeItem(at: file.0)) != nil { size -= file.1 }
        }
    }
}

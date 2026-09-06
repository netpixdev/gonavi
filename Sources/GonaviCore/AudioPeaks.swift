import Foundation

public struct WaveformLevel: Equatable, Sendable {
    public let peak: Float
    public let rms: Float
    public static let silence = WaveformLevel(peak: 0, rms: 0)
    public init(peak: Float, rms: Float) { self.peak = peak; self.rms = rms }
}

/// Source-time audio amplitudes. Values retain their original digital full-scale
/// reference: a quiet recording never grows to match a loud recording.
public struct WaveformData: Codable, Sendable {
    public let bucketDuration: Double
    public let duration: Double
    public let peaks: [Float]
    public let rms: [Float]
    private let summaries: [Summary]

    private struct Summary: Sendable {
        let stride: Int
        let peaks: [Float]
        let energy: [Double]
    }
    private enum CodingKeys: String, CodingKey { case bucketDuration, duration, peaks, rms }

    public init(bucketDuration: Double, duration: Double, peaks: [Float], rms: [Float]) throws {
        guard bucketDuration.isFinite, bucketDuration >= 0.001, bucketDuration <= 1,
              duration.isFinite, duration > 0, duration <= 86_400,
              peaks.count == rms.count, peaks.count == Int(ceil(duration / bucketDuration)),
              peaks.count <= 8_640_000 else {
            throw ProjectError.invalid("Dalga formu verisi geçersiz.")
        }
        for index in peaks.indices {
            let peak = peaks[index], level = rms[index]
            guard peak.isFinite, level.isFinite, peak >= 0, peak <= 1, level >= 0, level <= peak + Float(0.00001) else {
                throw ProjectError.invalid("Dalga formu seviyesi geçersiz.")
            }
        }
        self.bucketDuration = bucketDuration; self.duration = duration
        self.peaks = peaks; self.rms = rms
        // Small summary tiers make a full-day overview cheap to draw without
        // storing decoded PCM or scanning millions of buckets on every frame.
        var tiers: [Summary] = [], stride = 64
        while stride / 64 < peaks.count {
            let previous = tiers.last
            let sourceCount = previous?.peaks.count ?? peaks.count
            var tierPeaks: [Float] = [], tierEnergy: [Double] = []
            tierPeaks.reserveCapacity((sourceCount + 63) / 64)
            tierEnergy.reserveCapacity((sourceCount + 63) / 64)
            for start in Swift.stride(from: 0, to: sourceCount, by: 64) {
                var peak: Float = 0, energy: Double = 0
                for index in start..<min(start + 64, sourceCount) {
                    if let previous {
                        peak = max(peak, previous.peaks[index]); energy += previous.energy[index]
                    } else {
                        peak = max(peak, peaks[index])
                        energy += Double(rms[index]) * Double(rms[index]) * min(bucketDuration, duration - Double(index) * bucketDuration)
                    }
                }
                tierPeaks.append(peak); tierEnergy.append(energy)
            }
            tiers.append(Summary(stride: stride, peaks: tierPeaks, energy: tierEnergy))
            if tierPeaks.count == 1 { break }
            stride *= 64
        }
        summaries = tiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(bucketDuration: container.decode(Double.self, forKey: .bucketDuration),
                      duration: container.decode(Double.self, forKey: .duration),
                      peaks: container.decode([Float].self, forKey: .peaks),
                      rms: container.decode([Float].self, forKey: .rms))
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bucketDuration, forKey: .bucketDuration)
        try container.encode(duration, forKey: .duration)
        try container.encode(peaks, forKey: .peaks)
        try container.encode(rms, forKey: .rms)
    }

    /// Peak and time-weighted RMS in the intersecting source-time range.
    /// RMS resolution is one bucket (normally 10 ms); this is not a VAD.
    public func level(in range: Range<Double>) -> WaveformLevel {
        guard range.lowerBound.isFinite, range.upperBound.isFinite else { return .silence }
        let lower = max(0, range.lowerBound), upper = min(duration, range.upperBound)
        guard upper > lower else { return .silence }
        var index = max(0, Int(floor(lower / bucketDuration)))
        let end = min(peaks.count, Int(ceil(upper / bucketDuration)))
        var peak: Float = 0, energy: Double = 0
        while index < end {
            let bucketStart = Double(index) * bucketDuration
            var consumed = false
            if bucketStart >= lower {
                for tier in summaries.reversed() where index % tier.stride == 0 {
                    let next = index + tier.stride
                    if next <= end && Double(next) * bucketDuration <= upper {
                        peak = max(peak, tier.peaks[index / tier.stride])
                        energy += tier.energy[index / tier.stride]
                        index = next; consumed = true; break
                    }
                }
            }
            if consumed { continue }
            let length = max(0, min(upper, bucketStart + bucketDuration) - max(lower, bucketStart))
            peak = max(peak, peaks[index])
            energy += Double(rms[index]) * Double(rms[index]) * length
            index += 1
        }
        return WaveformLevel(peak: peak, rms: min(peak, Float(sqrt(max(0, energy / (upper - lower))))))
    }
}

/// Streaming reduction. Timestamp gaps remain silent, and overlapping decoder
/// buffers are ignored rather than counted twice. Only the current PCM buffer
/// and compact output buckets need to be resident in memory.
public struct AudioPeakAccumulator {
    public let sampleRate: Int
    public let bucketDuration: Double
    private let duration: Double
    private let totalFrames: Int
    private let framesPerBucket: Int
    private var peaks: [Float]
    private var rms: [Float]
    private var currentBucket = -1
    private var currentPeak: Float = 0
    private var currentEnergy: Double = 0
    private var nextFrame = 0

    public init(duration: Double, sampleRate: Int = 16_000, bucketsPerSecond: Int = 100) throws {
        guard duration.isFinite, duration > 0, duration <= 86_400,
              sampleRate >= 1, sampleRate <= 192_000,
              bucketsPerSecond >= 1, bucketsPerSecond <= 100,
              sampleRate % bucketsPerSecond == 0 else {
            throw ProjectError.invalid("Dalga formu süresi veya örnekleme ayarı geçersiz.")
        }
        self.duration = duration; self.sampleRate = sampleRate
        bucketDuration = 1 / Double(bucketsPerSecond)
        totalFrames = Int(ceil(duration * Double(sampleRate)))
        framesPerBucket = sampleRate / bucketsPerSecond
        let count = Int(ceil(duration / bucketDuration))
        peaks = Array(repeating: 0, count: count); rms = Array(repeating: 0, count: count)
    }

    public mutating func append(_ samples: UnsafeBufferPointer<Float>, at timestamp: Double, channels: Int = 1) throws {
        guard timestamp.isFinite, abs(timestamp) <= 172_800, (1...32).contains(channels), samples.count % channels == 0 else {
            throw ProjectError.invalid("Ses zaman kodu geçersiz.")
        }
        let startFrame = Int((timestamp * Double(sampleRate)).rounded())
        let skip = max(0, nextFrame - startFrame)
        let frameCount = samples.count / channels
        guard skip < frameCount else { return }
        for offset in skip..<frameCount {
            let frame = startFrame + offset
            if frame < 0 { continue }
            if frame >= totalFrames { break }
            let bucket = frame / framesPerBucket
            guard bucket < peaks.count else { break }
            if bucket != currentBucket {
                finishCurrentBucket(); currentBucket = bucket
                currentPeak = 0; currentEnergy = 0
            }
            var energy = 0.0
            for channel in 0..<channels {
                let sample = samples[offset * channels + channel]
                let amplitude = sample.isFinite ? min(1, abs(sample)) : 0
                currentPeak = max(currentPeak, amplitude)
                energy += Double(amplitude) * Double(amplitude)
            }
            currentEnergy += energy / Double(channels)
            nextFrame = frame + 1
        }
    }

    public mutating func finish() throws -> WaveformData {
        finishCurrentBucket()
        return try WaveformData(bucketDuration: bucketDuration, duration: duration, peaks: peaks, rms: rms)
    }

    private mutating func finishCurrentBucket() {
        guard currentBucket >= 0, currentBucket < peaks.count else { return }
        peaks[currentBucket] = currentPeak
        let frames = min(framesPerBucket, totalFrames - currentBucket * framesPerBucket)
        rms[currentBucket] = min(currentPeak, Float(sqrt(currentEnergy / Double(max(1, frames)))))
    }
}

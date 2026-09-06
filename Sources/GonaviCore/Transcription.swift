import Foundation

/// whisper-cli JSON offsets are milliseconds relative to the supplied audio.
public enum WhisperTranscript {
    private struct Document: Decodable { let transcription: [Segment] }
    private struct Segment: Decodable { let text: String; let offsets: Offsets }
    private struct Offsets: Decodable { let from: Double; let to: Double }

    public static func captions(from data: Data, offset: EditTime = .zero,
                                limit: EditTime, style: CaptionStyle = .clean) throws -> [Caption] {
        guard data.count <= 32_000_000, offset >= .zero, limit > .zero,
              limit.seconds <= 86_400, offset.ticks <= Int64.max - limit.ticks else {
            throw ProjectError.invalid("Altyazı zaman aralığı geçersiz.")
        }
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) }
        catch { throw ProjectError.invalid("Konuşma motorunun altyazı çıktısı okunamadı.") }
        guard document.transcription.count <= 100_000 else {
            throw ProjectError.invalid("Altyazı sayısı sınırı aşıldı.")
        }
        for segment in document.transcription {
            guard segment.offsets.from.isFinite, segment.offsets.to.isFinite,
                  segment.offsets.from >= 0, segment.offsets.to >= segment.offsets.from,
                  segment.offsets.to <= 86_400_000, segment.text.count <= 100_000 else {
                throw ProjectError.invalid("Konuşma motoru geçersiz zaman kodu üretti.")
            }
        }
        var result: [Caption] = []
        var previousEnd = EditTime.zero
        for segment in document.transcription.sorted(by: { $0.offsets.from < $1.offsets.from }) {
            let text = segment.text.replacingOccurrences(of: #"\[_[^\]]*\]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard !text.isEmpty else { continue }
            let start = max(previousEnd, EditTime(seconds: segment.offsets.from / 1000))
            let end = min(limit, EditTime(seconds: segment.offsets.to / 1000))
            guard end > start else { continue }
            // CLI produces word-boundary segments of <=42 characters. This fallback
            // also bounds externally supplied long segments; timings are approximate.
            var chunks: [String] = [], current = ""
            for word in text.split(separator: " ") {
                var remainder = String(word)
                while remainder.count > 80 {
                    if !current.isEmpty { chunks.append(current); current = "" }
                    chunks.append(String(remainder.prefix(80))); remainder = String(remainder.dropFirst(80))
                }
                if !current.isEmpty && current.count + remainder.count + 1 > 80 {
                    chunks.append(current); current = ""
                }
                if !remainder.isEmpty { current += (current.isEmpty ? "" : " ") + remainder }
            }
            if !current.isEmpty { chunks.append(current) }
            let total = max(1, chunks.reduce(0) { $0 + $1.count })
            var consumed = 0
            for chunk in chunks {
                let a = start + EditTime(ticks: (end - start).ticks * Int64(consumed) / Int64(total))
                consumed += chunk.count
                let b = start + EditTime(ticks: (end - start).ticks * Int64(consumed) / Int64(total))
                guard b > a else { continue }
                var caption = Caption(start: offset + a, duration: b - a, text: chunk)
                caption.style = style; result.append(caption)
            }
            previousEnd = end
        }
        return result
    }
}

import GonaviCore
import SwiftUI

struct AudioPreview: View {
    @ObservedObject var store: EditorStore
    @ObservedObject var waveforms: WaveformStore
    init(store: EditorStore) { self.store = store; waveforms = store.waveforms }
    private var source: MediaSource? {
        if let clip = store.activeClip { return store.project.sources.first { $0.id == clip.sourceID } }
        return store.project.sources.first { $0.id == store.project.clips.first?.sourceID || $0.id == store.project.music?.sourceID }
    }
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.accent)
            Text(source?.name ?? "Ses projesi").font(.system(size: 17, weight: .medium)).lineLimit(1)
            Canvas { context, size in
                guard let source, case .ready(let waveform) = waveforms.entries[source.id] else { return }
                var peaks = Path(), rms = Path()
                let count = max(1, Int(size.width / 3))
                for index in 0..<count {
                    let a = Double(index) / Double(count) * waveform.duration
                    let b = Double(index + 1) / Double(count) * waveform.duration
                    let level = waveform.level(in: a..<b)
                    let height: CGFloat = CGFloat(sqrt(Double(level.peak))) * size.height
                    let inner: CGFloat = CGFloat(sqrt(Double(level.rms))) * size.height
                    peaks.addRect(CGRect(x: CGFloat(index) * 3, y: (size.height - height) / 2, width: 2, height: max(0.5, height)))
                    rms.addRect(CGRect(x: CGFloat(index) * 3, y: (size.height - inner) / 2, width: 2, height: inner))
                }
                context.fill(peaks, with: .color(Theme.accent.opacity(0.4)))
                context.fill(rms, with: .color(Theme.accent))
            }.frame(height: 64)
            Text("SES ÇALIŞMA ALANI").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.secondary)
            Text("Bölün, taşıyın, altyazı oluşturun. M4A olarak dışa aktarın.")
                .font(.caption).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

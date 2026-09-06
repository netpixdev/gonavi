import AVFoundation
import GonaviCore
import SwiftUI

@MainActor final class SilenceController: ObservableObject {
    @Published var thresholdDB = -38.0
    @Published var minimumDuration = 0.5
    @Published var padding = 0.12
    @Published var onlySelected: Bool
    @Published var selected: Set<UUID> = []
    @Published private(set) var working = false
    @Published private(set) var progress = 0.0
    @Published private(set) var message = ""
    @Published private(set) var failure: String?
    @Published private(set) var result: SilenceEngine.Result?
    @Published private(set) var auditionID: UUID?
    private(set) var baseRevision = 0
    private var task: Task<Void, Never>?
    private var auditionTask: Task<Void, Never>?
    private var auditionToken = UUID()
    private var generation = UUID()
    init(hasSelection: Bool) { onlySelected = hasSelection }
    var chosen: [SilenceCandidate] { result?.candidates.filter { selected.contains($0.id) } ?? [] }
    var removedSeconds: Double { chosen.reduce(0) { $0 + $1.duration.seconds } }

    func generate(store: EditorStore) {
        guard !working else { return }
        guard !onlySelected || store.activeClip != nil else {
            failure = "Analiz için bir klip seçin veya Tüm kurgu kapsamını kullanın."; return
        }
        stopAudition(store: store)
        let project = store.project
        let ids: Set<UUID>? = onlySelected ? store.selectedClip.map { Set([$0]) } : nil
        let settings = SilenceSettings(thresholdDB: thresholdDB, minimumDuration: minimumDuration, padding: padding)
        baseRevision = store.revision; working = true; failure = nil; result = nil; selected = []
        progress = 0; message = "Kaynak sesleri inceleniyor…"
        let token = UUID(); generation = token
        task = Task { [weak self] in
            do {
                let result = try await SilenceEngine.analyze(project: project, clipIDs: ids, settings: settings) { [weak self] message, progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token, self.working else { return }
                        self.message = message; self.progress = progress
                    }
                }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.result = result; self.selected = Set(result.candidates.map(\.id))
                self.progress = 1; self.message = result.candidates.isEmpty ? "Bu ayarlarla kesilecek sessizlik bulunamadı." : "Kesimleri dinleyip seçiminizi yapın."
            } catch {
                guard let self, self.generation == token else { return }
                if Task.isCancelled { self.message = "Analiz iptal edildi. Projeniz korunuyor." }
                else { self.failure = error.localizedDescription; self.message = "Analiz tamamlanamadı." }
            }
            guard let self, self.generation == token else { return }
            self.working = false; self.task = nil
        }
    }
    func cancel() { task?.cancel(); message = "İptal ediliyor…" }
    func reset(store: EditorStore) { stopAudition(store: store); result = nil; selected = []; message = ""; failure = nil }
    func apply(store: EditorStore) {
        stopAudition(store: store)
        do { try store.applySilences(chosen, expectedRevision: baseRevision) }
        catch { failure = error.localizedDescription }
    }
    func stopAudition(store: EditorStore) {
        auditionToken = UUID(); auditionTask?.cancel(); auditionTask = nil; auditionID = nil
        store.player.pause(); store.isPlaying = false
    }
    func audition(_ candidate: SilenceCandidate, store: EditorStore) {
        let same = auditionID == candidate.id
        stopAudition(store: store)
        guard !same else { return }
        let token = UUID(); auditionToken = token; auditionID = candidate.id
        let start = max(0, candidate.start.seconds - 0.25)
        let end = min(store.project.duration.seconds, candidate.end.seconds + 0.25)
        auditionTask = Task { [weak self, weak store] in
            guard let store else { return }
            let positioned = await store.player.seek(to: CMTime(seconds: start, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
            guard positioned, !Task.isCancelled, self?.auditionToken == token else {
                if self?.auditionToken == token { self?.stopAudition(store: store) }
                return
            }
            store.playhead = start; store.player.play(); store.isPlaying = true
            do {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    if store.player.currentTime().seconds >= end || store.player.currentItem?.status == .failed { break }
                }
            } catch {}
            guard self?.auditionToken == token else { return }
            self?.stopAudition(store: store); store.seek(candidate.start.seconds)
        }
    }
}

// Hallmark · component: silence review · existing Gonavi native theme.
// Settings, progress, cancellation, empty, error and selectable review states.
@MainActor struct SilenceView: View {
    @ObservedObject var store: EditorStore
    @StateObject private var controller: SilenceController
    init(store: EditorStore, controller: SilenceController? = nil) {
        self.store = store
        _controller = StateObject(wrappedValue: controller ?? SilenceController(hasSelection: store.activeClip != nil))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sessizlikleri temizle").font(.system(size: 25, weight: .semibold))
                    Text("Duraklamaları kısaltın. Ritmi siz belirleyin.").foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { close() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Kapat").disabled(controller.working)
            }
            if let result = controller.result { review(result) } else { settings }
            if controller.working {
                VStack(alignment: .leading, spacing: 10) {
                    Text(controller.message).font(.callout)
                    ProgressView(value: controller.progress)
                }.padding(16).background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
            } else if controller.result == nil && !controller.message.isEmpty {
                Text(controller.message).font(.callout).foregroundStyle(Theme.secondary)
            }
            if let failure = controller.failure {
                Label(failure, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Color(nsColor: Theme.captionColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Ana kurgu sesi analiz edilir. Klipler ve altyazılar birlikte kısalır; arka plan müziği kesilmez, yeni proje süresine uyarlanır. Kaynak dosyalar değişmez.")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                if controller.working { Button("Analizi İptal Et", action: controller.cancel) }
                else { Button("Kapat", action: close).keyboardShortcut(.cancelAction) }
                Spacer()
                if controller.result != nil {
                    Button("Ayarları Değiştir") { controller.reset(store: store) }
                    Button("\(controller.chosen.count) Kesimi Uygula") { controller.apply(store: store) }
                        .buttonStyle(StudioButtonStyle(primary: true)).keyboardShortcut(.defaultAction).disabled(controller.chosen.isEmpty)
                } else {
                    Button("Sessizlikleri Analiz Et") { controller.generate(store: store) }
                        .buttonStyle(StudioButtonStyle(primary: true)).keyboardShortcut(.defaultAction).disabled(controller.working)
                }
            }
        }.padding(24).frame(width: 740).background(Theme.panel).tint(Theme.accent)
            .interactiveDismissDisabled()
            .onDisappear { controller.cancel(); controller.stopAudition(store: store) }
    }
    private func close() { controller.stopAudition(store: store); store.showingSilences = false }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Kapsam", selection: $controller.onlySelected) {
                Text("Tüm kurgu").tag(false)
                Text("Seçili klip").tag(true).disabled(store.activeClip == nil)
            }.pickerStyle(.segmented)
            setting("Ses eşiği", value: $controller.thresholdDB, range: -60 ... -20, step: 1, suffix: "dBFS", decimals: 0)
            setting("En az sessizlik", value: $controller.minimumDuration, range: 0.2 ... 3, step: 0.1, suffix: "sn", decimals: 1)
            setting("Uçlarda korunan pay", value: $controller.padding, range: 0 ... 0.5, step: 0.02, suffix: "sn", decimals: 2)
            Text("Eşik yükseldikçe daha fazla düşük ses kesime aday olur. Pay, her sessizliğin iki ucunda sesi korur. Bu analiz ses seviyesine dayanır; konuşmayı tanıyan bir model değildir.")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Label("Bu Mac’te · Ücretsiz · Model indirmeden", systemImage: "internaldrive").font(.callout).foregroundStyle(Theme.accent)
        }.disabled(controller.working)
    }
    private func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String, decimals: Int) -> some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 160, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue }, set: { proposed in
                value.wrappedValue = min(range.upperBound, max(range.lowerBound, (proposed / step).rounded() * step))
            }), in: range).accessibilityLabel(title)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                    case .decrement: value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                    @unknown default: break
                    }
                }
            Text(String(format: "%.*f %@", decimals, value.wrappedValue, suffix)).font(.callout.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
        }
    }
    @ViewBuilder private func review(_ result: SilenceEngine.Result) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.2f sn kısalacak", controller.removedSeconds)).font(.title2.weight(.semibold))
                Text("\(controller.selected.count) / \(result.candidates.count) kesim seçili · Tek ⌘Z ile geri alabilirsiniz.").font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if !result.candidates.isEmpty {
                Button(controller.selected.count == result.candidates.count ? "Seçimi Kaldır" : "Tümünü Seç") {
                    controller.selected = controller.selected.count == result.candidates.count ? [] : Set(result.candidates.map(\.id))
                }.buttonStyle(.borderless)
            }
        }
        if result.candidates.isEmpty {
            Label("Bu ayarlarla kesilecek sessizlik bulunamadı.", systemImage: "checkmark.circle")
                .padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(result.candidates) { candidate in
                        HStack(spacing: 14) {
                            Toggle("Kesimi seç", isOn: Binding(get: { controller.selected.contains(candidate.id) }, set: { enabled in
                                if enabled { controller.selected.insert(candidate.id) } else { controller.selected.remove(candidate.id) }
                            })).toggleStyle(.checkbox).labelsHidden()
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sourceName(candidate)).font(.callout).lineLimit(1).truncationMode(.middle)
                                Text("\(stamp(candidate.start.seconds)) → \(stamp(candidate.end.seconds))")
                                    .font(.caption.monospaced()).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Text(String(format: "−%.2f sn", candidate.duration.seconds)).font(.callout.monospacedDigit()).foregroundStyle(Color(nsColor: Theme.captionColor))
                            Button { controller.audition(candidate, store: store) } label: {
                                Label(controller.auditionID == candidate.id ? "Durdur" : "Dinle", systemImage: controller.auditionID == candidate.id ? "stop.fill" : "play.fill").frame(width: 64)
                            }.buttonStyle(.borderless).disabled(store.isBuilding || store.player.currentItem == nil)
                        }.padding(12)
                        Divider()
                    }
                }
            }.frame(height: 190).background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
            Text("Dinle, kesim aralığını iki yanında 0,25 sn ile çalar. Kısık konuşma veya nefesleri korumak için ilgili kesimin seçimini kaldırın.")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if !result.skippedSources.isEmpty {
            Text("Ses hattı olmadığı için atlandı: " + result.skippedSources.joined(separator: ", "))
                .font(.caption).foregroundStyle(Theme.secondary).lineLimit(2)
        }
    }
    private func sourceName(_ candidate: SilenceCandidate) -> String {
        let sourceID = store.project.clips.first { $0.id == candidate.clipID }?.sourceID
        return store.project.sources.first { $0.id == sourceID }?.name ?? "Klip"
    }
    private func stamp(_ seconds: Double) -> String {
        String(format: "%02d:%05.2f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}

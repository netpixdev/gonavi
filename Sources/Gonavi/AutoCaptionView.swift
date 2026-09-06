import GonaviCore
import SwiftUI

@MainActor
final class AutoCaptionController: ObservableObject {
    @Published var model: CaptionModel = .small
    @Published var style: CaptionStyle = .clean
    @Published private(set) var working = false
    @Published private(set) var message = ""
    @Published private(set) var progress: Double?
    @Published private(set) var failure: String?
    @Published private(set) var captions: [Caption]?
    @Published private(set) var started = Date()
    private var task: Task<Void, Never>?

    func generate(_ project: Project) {
        guard !working else { return }
        working = true; failure = nil; captions = nil; progress = nil; started = Date()
        message = "Konuşma modeli hazırlanıyor…"
        let selected = model, selectedStyle = style
        task = Task {
            do {
                let report: CaptionEngine.Report = { [weak self] text, fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.working else { return }
                        self.message = text; self.progress = fraction
                    }
                }
                let url = try await CaptionEngine.ensureModel(selected, report: report)
                let result = try await CaptionEngine.transcribe(project: project, model: url, style: selectedStyle, report: report)
                try Task.checkCancellation()
                captions = result; message = result.isEmpty ? "Konuşma bulunamadı." : "\(result.count) altyazı hazır."
            } catch {
                if Task.isCancelled { message = "İşlem iptal edildi. Projeniz korunuyor." }
                else { failure = error.localizedDescription; message = "Altyazı üretilemedi." }
            }
            working = false; task = nil
        }
    }
    func cancel() { task?.cancel(); message = "İptal ediliyor…" }
    func removeModel() {
        guard !working else { return }
        do { if model.installed { try FileManager.default.removeItem(at: model.localURL) }; failure = nil; message = "Model kaldırıldı. Yeniden indirebilirsiniz." }
        catch { failure = error.localizedDescription }
    }
}

// Hallmark · component: caption sheet · existing Gonavi theme
// Native focus, pressed and disabled states; explicit loading/error/empty/review states.
@MainActor struct AutoCaptionView: View {
    @ObservedObject var store: EditorStore
    @StateObject private var controller: AutoCaptionController
    init(store: EditorStore, controller: AutoCaptionController? = nil) {
        self.store = store; _controller = StateObject(wrappedValue: controller ?? AutoCaptionController())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Otomatik altyazı").font(.system(size: 25, weight: .semibold))
                    Text("Türkçe · Bu Mac’te · Ücretsiz").foregroundStyle(Theme.accent)
                }
                Spacer()
                Button { store.showingAutoCaptions = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Kapat").disabled(controller.working)
            }
            if let captions = controller.captions {
                result(captions)
            } else {
                options
            }
            if controller.working {
                VStack(alignment: .leading, spacing: 10) {
                    Text(controller.message).font(.callout)
                    if let value = controller.progress { ProgressView(value: value) }
                    else { ProgressView().controlSize(.small) }
                    TimelineView(.periodic(from: controller.started, by: 1)) { context in
                        let seconds = max(0, Int(context.date.timeIntervalSince(controller.started)))
                        Text("Geçen süre: \(seconds / 60) dk \(seconds % 60) sn · Intel Mac’te uzun videolar zaman alabilir.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }.padding(16).background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
            } else if !controller.message.isEmpty && controller.captions == nil {
                Text(controller.message).font(.callout).foregroundStyle(Theme.secondary)
            }
            if let failure = controller.failure {
                VStack(alignment: .leading, spacing: 8) {
                    Label("İşlem tamamlanamadı", systemImage: "exclamationmark.triangle").font(.headline)
                    ScrollView { Text(failure).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 85)
                    if controller.model.installed { Button("Modeli Kaldır ve Yeniden İndirmeye Hazırla", action: controller.removeModel) }
                }
            }
            Divider()
            HStack {
                if controller.working {
                    Button("İşlemi İptal Et", action: controller.cancel)
                } else {
                    Button("Kapat") { store.showingAutoCaptions = false }.keyboardShortcut(.cancelAction)
                }
                Spacer()
                if let captions = controller.captions, !captions.isEmpty {
                    Button(store.project.captions.isEmpty ? "Altyazıları Ekle" : "Mevcut Altyazıları Değiştir") {
                        store.applyGeneratedCaptions(captions)
                    }.buttonStyle(StudioButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
                } else {
                    Button(controller.model.installed ? "Altyazı Oluştur" : "Modeli İndir ve Oluştur") { controller.generate(store.project) }
                        .buttonStyle(StudioButtonStyle(primary: true)).keyboardShortcut(.defaultAction).disabled(controller.working)
                }
            }
        }
        .padding(28).frame(width: 620).background(Theme.panel).tint(Theme.accent)
        .interactiveDismissDisabled()
    }
    private var options: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Kalite", selection: $controller.model) {
                ForEach(CaptionModel.allCases) { model in Text(model.title).tag(model) }
            }
            Text(controller.model.detail).font(.callout).foregroundStyle(Theme.secondary)
            Picker("Altyazı şablonu", selection: $controller.style) {
                ForEach(CaptionStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Divider()
            Label(controller.model.installed ? "Model bu Mac’te hazır" : "İlk kullanımda model indirilir", systemImage: controller.model.installed ? "checkmark.circle" : "arrow.down.circle")
                .font(.callout)
            Text("İndirmeden sonra internet gerekmez. Videolarınız ve sesiniz gönderilmez. Ana kurgu kliplerinin orijinal sesi kullanılır; eklediğiniz müzik işleme dahil edilmez.")
                .font(.caption).foregroundStyle(Theme.secondary)
            Text("Sonucu eklemeden önce inceleyebilirsiniz. Mevcut altyazılarınız siz uygulayana kadar korunur.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }.disabled(controller.working)
    }
    @ViewBuilder private func result(_ captions: [Caption]) -> some View {
        if captions.isEmpty {
            Text("Konuşma bulunamadı. Videonun orijinal sesini kontrol edin veya farklı kalite seçerek tekrar deneyin.").foregroundStyle(Theme.secondary)
            options
        } else {
            HStack { Text("\(captions.count) altyazı hazır").font(.headline); Spacer(); Text("Önizleme").foregroundStyle(Theme.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(captions) { caption in
                        HStack(alignment: .top, spacing: 16) {
                            Text(String(format: "%02d:%02d", Int(caption.start.seconds) / 60, Int(caption.start.seconds) % 60))
                                .font(.caption.monospaced()).foregroundStyle(Theme.secondary).frame(width: 50)
                            Text(caption.text).font(.callout).textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                }.padding(14)
            }.frame(height: 250).background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
            Text("Yazım ve zamanları editörde düzeltebilirsiniz. Uygulama tek adımda geri alınır (⌘Z).")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}

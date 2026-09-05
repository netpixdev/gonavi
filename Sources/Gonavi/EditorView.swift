import AVKit
import GonaviCore
import SwiftUI
import UniformTypeIdentifiers

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.controlsStyle = .none
        view.videoGravity = .resizeAspect; view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
}

struct EditorView: View {
    @ObservedObject var store: EditorStore
    @State private var inspectorTab = 0
    @State private var pixelsPerSecond = 32.0
    @State private var dropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                mediaPanel.frame(minWidth: 200, idealWidth: 235, maxWidth: 290)
                preview.frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                inspector.frame(minWidth: 260, idealWidth: 285, maxWidth: 330)
            }
            Divider()
            timeline.frame(height: 230)
            Divider()
            HStack(spacing: 10) {
                if store.importing { ProgressView().controlSize(.small) }
                Text(store.status).lineLimit(1)
                Spacer()
                Text("\(store.project.scene.width) × \(store.project.scene.height) · \(store.project.fps) fps")
            }.font(.caption).foregroundStyle(Theme.secondary).padding(.horizontal, 16).frame(height: 28)
        }
        .background(Theme.canvas).tint(Theme.accent)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 6) {
                    Text("GONAVI").font(.system(size: 13, weight: .black, design: .rounded)).tracking(2)
                    Text("/  \(store.project.name)\(store.dirty ? " •" : "")").foregroundStyle(Theme.secondary)
                }
            }
            ToolbarItemGroup {
                Button(action: store.chooseMedia) { Label("Medya Ekle", systemImage: "plus") }.disabled(!store.editable)
                Button { store.save() } label: { Image(systemName: "square.and.arrow.down") }.help("Projeyi kaydet · ⌘S")
                Button(action: store.undo) { Image(systemName: "arrow.uturn.backward") }.disabled(!store.canUndo || !store.editable).help("Geri al · ⌘Z")
                Button(action: store.exportVideo) { Label("Dışa Aktar", systemImage: "arrow.up.right") }.disabled(!store.canExport)
            }
        }
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Tamam") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .sheet(isPresented: Binding(get: { store.exporting }, set: { _ in })) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Video hazırlanıyor").font(.title2.bold())
                Text("\(store.project.scene.width) × \(store.project.scene.height) · MP4").foregroundStyle(Theme.secondary)
                ProgressView(value: Double(store.exportProgress))
                HStack { Text("%\(Int(store.exportProgress * 100))").monospacedDigit(); Spacer(); Button("İptal", action: store.cancelExport) }
            }.padding(32).frame(width: 420).interactiveDismissDisabled()
        }
    }

    private var mediaPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelTitle("MEDYA", trailing: "\(store.project.sources.count) dosya")
            if store.project.sources.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "film.stack").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accent)
                    Text("İlk görüntüyle\nbaşlayın.").font(.title2.weight(.semibold))
                    Text("Video ve ses dosyalarını buraya bırakın veya bilgisayarınızdan seçin.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                    Button("Dosya Seç…", action: store.chooseMedia).disabled(!store.editable)
                }.padding(20)
            } else {
                List(store.project.sources) { source in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: source.isVideo ? "film" : "waveform").foregroundStyle(Theme.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(source.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Text(clock(source.duration.seconds)).font(.caption.monospaced()).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 0)
                        Button { store.addSource(source) } label: { Image(systemName: "plus") }
                            .buttonStyle(.borderless).help("Kurguya ekle").disabled(!store.editable)
                    }.padding(.vertical, 7)
                    .contextMenu { Button("Dosyayı Yeniden Bağla…") { store.relink(source) }.disabled(!store.editable) }
                }.listStyle(.sidebar)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                Label("Dosyalarınız bu Mac’te kalır", systemImage: "internaldrive")
                Text("Kaynak videolar değiştirilmez.").foregroundStyle(Theme.secondary)
            }.font(.caption).padding(16)
        }
        .background(dropTarget ? Theme.accent.opacity(0.1) : Theme.panel)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTarget) { providers in
            guard store.editable else { return false }
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else { url = item as? URL }
                    if let url { Task { @MainActor in store.importURLs([url]) } }
                }
            }
            return true
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ÖNİZLEME").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                Spacer()
                Text(store.project.scene.rawValue).font(.caption.monospaced()).foregroundStyle(Theme.secondary)
            }.padding(16)
            ZStack {
                if store.project.clips.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle").font(.system(size: 46, weight: .ultraLight))
                        Text("Hikâyeniz burada şekillenecek.").font(.callout)
                        Text("Bir video ekleyin · ⌘I").font(.caption).foregroundStyle(Theme.secondary)
                    }.foregroundStyle(Theme.secondary)
                } else {
                    PlayerSurface(player: store.player)
                        .aspectRatio(CGFloat(store.project.scene.width) / CGFloat(store.project.scene.height), contentMode: .fit)
                        .padding(16)
                }
                if store.isBuilding { ProgressView("Önizleme hazırlanıyor…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.inset)
            HStack(spacing: 16) {
                Text(clock(store.playhead)).monospacedDigit().frame(width: 80, alignment: .leading)
                Spacer()
                Button { store.seek(max(0, store.playhead - 1 / Double(store.project.fps))) } label: { Image(systemName: "backward.end") }.help("Bir kare geri")
                Button(action: store.togglePlayback) { Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").frame(width: 28) }
                    .disabled(store.project.clips.isEmpty || store.isBuilding).help("Oynat / duraklat")
                Button { store.seek(store.playhead + 1 / Double(store.project.fps)) } label: { Image(systemName: "forward.end") }.help("Bir kare ileri")
                Spacer()
                Text(clock(store.project.duration.seconds)).monospacedDigit().foregroundStyle(Theme.secondary).frame(width: 80, alignment: .trailing)
            }.buttonStyle(.borderless).padding(16)
        }
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("Özellikler", selection: $inspectorTab) {
                Text("Sahne").tag(0); Text("Klip").tag(1); Text("Altyazı").tag(2)
            }.pickerStyle(.segmented).padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if inspectorTab == 0 { sceneInspector }
                    else if inspectorTab == 1 { clipInspector }
                    else { captionInspector }
                }.padding(16).disabled(!store.editable)
            }
        }.background(Theme.panel)
    }
    private var sceneInspector: some View {
        Group {
            Text("Sahne ayarları").font(.headline)
            TextField("Proje adı", text: Binding(get: { store.project.name }, set: { value in store.mutate { $0.name = value } }))
            Picker("Oran", selection: Binding(get: { store.project.scene }, set: { value in store.mutate { $0.scene = value } })) {
                ForEach(ScenePreset.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Kare hızı", selection: Binding(get: { store.project.fps }, set: { value in store.mutate { $0.fps = value } })) {
                ForEach([24, 25, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
            }
            Divider()
            Text("Müzik").font(.headline)
            if let music = store.project.music {
                Text(store.project.sources.first { $0.id == music.sourceID }?.name ?? "Müzik").font(.caption)
                valueSlider("Ses", value: Binding(get: { store.project.music?.volume ?? 0 }, set: { value in store.mutate { $0.music?.volume = value } }), range: 0...1)
                Button("Müziği Kaldır") { store.mutate { $0.music = nil } }
            } else { Text("Bir ses dosyası ekleyin. Müzik başlangıçtan çalar; video süresinde sonlanır.").font(.caption).foregroundStyle(Theme.secondary) }
            Divider()
            Text("İlk teknik sürüm").font(.headline)
            Text("Tek video hattı, müzik ve elle altyazı. Otomatik altyazı, sessizlik temizleme ve çoklu video katmanları sonraki aşamada.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }
    @ViewBuilder private var clipInspector: some View {
        if let clip = store.activeClip {
            Text("Görüntü ve ses").font(.headline)
            Text(store.project.sources.first { $0.id == clip.sourceID }?.name ?? "Klip").font(.caption).foregroundStyle(Theme.secondary)
            Toggle("Sahneyi doldur (crop)", isOn: Binding(get: { store.activeClip?.fill ?? false }, set: { value in store.updateClip { $0.fill = value } }))
            valueSlider("Zoom", value: clipBinding(\.zoom), range: 1...4)
            valueSlider("Yatay konum", value: clipBinding(\.offsetX), range: -1...1)
            valueSlider("Dikey konum", value: clipBinding(\.offsetY), range: -1...1)
            valueSlider("Ses seviyesi", value: clipBinding(\.volume), range: 0...2)
            Button("Görüntüyü Sıfırla") { store.updateClip { $0.zoom = 1; $0.offsetX = 0; $0.offsetY = 0; $0.fill = false } }
            Divider()
            Text("Kaynak: \(clock(clip.sourceStart.seconds)) – \(clock((clip.sourceStart + clip.duration).seconds))").font(.caption.monospaced())
            Text("Kırpmak için oynatma çizgisini konumlandırın, klibi bölün ve istemediğiniz parçayı silin.").font(.caption).foregroundStyle(Theme.secondary)
            Button("Oynatma Çizgisinde Böl", action: store.split)
            Button("Klibi Sil", role: .destructive, action: store.deleteClip)
        } else { Text("Timeline’dan bir klip seçin.").foregroundStyle(Theme.secondary) }
    }
    private var captionInspector: some View {
        Group {
            HStack { Text("Altyazılar").font(.headline); Spacer(); Button(action: store.addCaption) { Image(systemName: "plus") }.disabled(store.project.clips.isEmpty) }
            ForEach(store.project.captions) { caption in
                Button { store.selectedCaption = caption.id; store.seek(caption.start.seconds) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(caption.text).lineLimit(2)
                        Text(clock(caption.start.seconds)).font(.caption.monospaced()).foregroundStyle(Theme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(store.selectedCaption == caption.id ? Theme.caption : Theme.inset, in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain)
            }
            if let caption = store.project.captions.first(where: { $0.id == store.selectedCaption }) {
                TextField("Altyazı", text: Binding(get: { store.project.captions.first { $0.id == store.selectedCaption }?.text ?? "" }, set: { value in store.updateCaption { $0.text = value } }), axis: .vertical)
                    .lineLimit(2...6)
                Picker("Şablon", selection: Binding(get: { caption.style }, set: { value in store.updateCaption { $0.style = value } })) {
                    ForEach(CaptionStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                LabeledContent("Başlangıç (sn)") {
                    TextField("Başlangıç", value: Binding(get: { caption.start.seconds }, set: { value in store.updateCaption { $0.start = EditTime(seconds: value) } }), format: .number).frame(width: 75)
                }
                LabeledContent("Süre (sn)") {
                    TextField("Süre", value: Binding(get: { caption.duration.seconds }, set: { value in store.updateCaption { $0.duration = EditTime(seconds: value) } }), format: .number).frame(width: 75)
                }
                Button("Altyazıyı Sil", role: .destructive) { store.mutate { $0.captions.removeAll { $0.id == caption.id } } }
            }
            Button("SRT Dışa Aktar…", action: store.exportSRT).disabled(store.project.captions.isEmpty)
            Text("Altyazılar sahne zamanına bağlıdır. Klip silmek süreleri kaydırır; kliplerin yerini değiştirmek altyazıları taşımaz.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("KURGU").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                Button(action: store.split) { Label("Böl", systemImage: "scissors") }.disabled(store.activeClip == nil || !store.editable)
                Button(action: store.deleteClip) { Image(systemName: "trash") }.disabled(store.activeClip == nil || !store.editable).help("Seçili klibi sil")
                Spacer()
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $pixelsPerSecond, in: 4...100).frame(width: 100).accessibilityLabel("Timeline yakınlaştırma")
                Image(systemName: "plus.magnifyingglass")
            }.buttonStyle(.borderless).padding(.horizontal, 16).frame(height: 40)
            ScrollView(.horizontal) {
                let width = max(800, store.project.duration.seconds * pixelsPerSecond)
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.panel)
                        let interval = max(1, Int(ceil(70 / pixelsPerSecond)))
                        ForEach(Array(stride(from: 0, through: Int(width / pixelsPerSecond), by: interval)), id: \.self) { second in
                            Text(clock(Double(second))).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary)
                                .offset(x: Double(second) * pixelsPerSecond + 3)
                        }
                    }.frame(width: width, height: 24).clipped().contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { store.seek($0.location.x / pixelsPerSecond) })
                    HStack(spacing: 0) {
                        ForEach(store.project.clips) { clip in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(store.project.sources.first { $0.id == clip.sourceID }?.name ?? "Video", systemImage: "film").lineLimit(1)
                                Text(clock(clip.duration.seconds)).font(.caption2.monospaced()).foregroundStyle(Theme.secondary)
                            }.font(.caption).padding(.horizontal, 8).frame(width: max(1, clip.duration.seconds * pixelsPerSecond), height: 52, alignment: .leading)
                                .background(Theme.video).clipped()
                                .overlay(Rectangle().stroke(store.selectedClip == clip.id ? Theme.accent : Theme.rule, lineWidth: 2))
                                .contentShape(Rectangle())
                                .onTapGesture { store.selectedClip = clip.id; inspectorTab = 1; store.seek(store.project.start(of: clip.id).seconds) }
                                .draggable(clip.id.uuidString)
                                .dropDestination(for: String.self) { values, _ in
                                    guard let text = values.first, let id = UUID(uuidString: text), store.editable else { return false }
                                    store.moveClip(id, before: clip.id); return true
                                }
                        }
                    }.frame(height: 52)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.panel)
                        if let music = store.project.music {
                            Text("♫  " + (store.project.sources.first { $0.id == music.sourceID }?.name ?? "Müzik"))
                                .font(.caption).padding(.horizontal, 8)
                                .frame(width: min(store.project.duration.seconds, store.project.sources.first { $0.id == music.sourceID }?.duration.seconds ?? 0) * pixelsPerSecond, height: 28, alignment: .leading)
                                .background(Theme.audio).clipped()
                        } else { Text("Müzik hattı").font(.caption2).foregroundStyle(Theme.secondary).padding(.leading, 8) }
                    }.frame(width: width, height: 28)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.panel)
                        ForEach(store.project.captions) { caption in
                            Text(caption.text).font(.caption2).padding(.horizontal, 5)
                                .frame(width: max(1, caption.duration.seconds * pixelsPerSecond), height: 26, alignment: .leading)
                                .background(Theme.caption).clipped().offset(x: caption.start.seconds * pixelsPerSecond)
                                .onTapGesture { store.selectedCaption = caption.id; inspectorTab = 2; store.seek(caption.start.seconds) }
                        }
                    }.frame(width: width, height: 26)
                }.frame(width: width, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        Rectangle().fill(Theme.accent).frame(width: 1, height: 162)
                            .offset(x: store.playhead * pixelsPerSecond).allowsHitTesting(false)
                    }
                    .padding(.horizontal, 16)
            }
        }.background(Theme.inset)
    }

    private func clipBinding(_ path: WritableKeyPath<VideoClip, Double>) -> Binding<Double> {
        Binding(get: { store.activeClip?[keyPath: path] ?? 0 }, set: { value in store.updateClip { $0[keyPath: path] = value } })
    }
    private func valueSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(label); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(Theme.secondary) }.font(.caption)
            Slider(value: value, in: range).accessibilityLabel(label)
        }
    }
    private func panelTitle(_ title: String, trailing: String) -> some View {
        HStack { Text(title).fontWeight(.semibold).tracking(1.5); Spacer(); Text(trailing).foregroundStyle(Theme.secondary) }
            .font(.system(size: 10)).padding(16)
    }
    private func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds * 100))
        return String(format: "%02d:%02d.%02d", total / 6000, total / 100 % 60, total % 100)
    }
}

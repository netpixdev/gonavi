import AppKit
import GonaviCore
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var store: EditorStore
    var body: some View {
        Group {
            if store.showingHome { WelcomeView(store: store) }
            else { EditorView(store: store) }
        }
        .sheet(isPresented: $store.creatingProject) {
            NewProjectView(store: store)
        }
        .alert("İşlem tamamlanamadı", isPresented: Binding(
            get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("Tamam") { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
}

struct GonaviMark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RoundedRectangle(cornerRadius: 2).frame(width: 25, height: 5)
            RoundedRectangle(cornerRadius: 2).frame(width: 17, height: 5).offset(x: 8)
            RoundedRectangle(cornerRadius: 2).frame(width: 25, height: 5)
        }.foregroundStyle(Theme.accent).accessibilityHidden(true)
    }
}

struct WelcomeView: View {
    @ObservedObject var store: EditorStore
    @State private var search = ""
    private var matchingProjects: [RecentProject] {
        store.recentProjects.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 218)
            Rectangle().fill(Theme.rule).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HStack {
                        Label("KİŞİSEL ÇALIŞMA ALANINIZ", systemImage: "internaldrive")
                            .font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text("macOS · \(architecture)").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    HStack(alignment: .bottom, spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Bir sonraki\nhikâyeniz.")
                                .font(.system(size: 42, weight: .semibold, design: .rounded)).tracking(-1.2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Görüntülerinizi bir araya getirin.\nKurgulayın, altyazı ekleyin, paylaşmaya hazırlayın.")
                                .font(.system(size: 14)).foregroundStyle(Theme.secondary).lineSpacing(5)
                        }
                        Spacer(minLength: 0)
                        SceneGlyph(preset: .portrait, selected: true).frame(width: 100, height: 116)
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 14) {
                        Button(action: store.newProject) {
                            HStack(spacing: 16) {
                                Image(systemName: "plus").font(.system(size: 24, weight: .light))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Yeni proje").font(.system(size: 16, weight: .semibold))
                                    Text("Sahnenizi seçin, kurguyu başlatın.").font(.caption).opacity(0.8)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.padding(24).frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                        }.buttonStyle(WorkspaceActionStyle(primary: true))
                        Button(action: store.open) {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: "folder").font(.system(size: 20, weight: .light))
                                HStack { Text("Proje aç").fontWeight(.medium); Spacer(); Text("⌘O").foregroundStyle(Theme.secondary) }
                            }.padding(24).frame(width: 174, height: 100, alignment: .leading)
                        }.buttonStyle(WorkspaceActionStyle(primary: false))
                    }
                    if store.hasOpenProject || store.recoveryAvailable { continueRow }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Son projeler").font(.system(size: 18, weight: .semibold))
                            Spacer()
                            if !store.recentProjects.isEmpty {
                                TextField("Projelerde ara", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                            }
                        }
                        if store.recentProjects.isEmpty {
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: "square.stack").font(.system(size: 26, weight: .light)).foregroundStyle(Theme.secondary)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("İlk projenize yer ayırdık.").fontWeight(.medium)
                                    Text("Kaydettiğiniz ve açtığınız projeler burada görünür.\nBaşlamak için bir proje oluşturun veya .gonavi dosyanızı açın.")
                                        .font(.callout).foregroundStyle(Theme.secondary).lineSpacing(3)
                                }
                            }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.rule, style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
                        } else if matchingProjects.isEmpty {
                            Text("Bu adla bir proje bulunamadı.").foregroundStyle(Theme.secondary).padding(.vertical, 24)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(matchingProjects) { recent in
                                    recentRow(recent)
                                    if recent.id != matchingProjects.last?.id { Divider().padding(.leading, 72) }
                                }
                            }.background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                        Text("Dosyalarınız Mac’inizde kalır. Kaynak videolarınız değiştirilmez.")
                    }.font(.caption).foregroundStyle(Theme.secondary)
                }.padding(40).frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Theme.canvas)
        }.tint(Theme.accent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                GonaviMark()
                Text("gonavi").font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.7)
            }.padding(.bottom, 48)
            Label("Projeler", systemImage: "rectangle.stack").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent).frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            if store.hasOpenProject {
                Button(action: store.resumeProject) { Label("Editöre dön", systemImage: "arrow.right.to.line") }
                    .buttonStyle(.plain).padding(12).padding(.top, 8)
            }
            Spacer(minLength: 36)
            VStack(alignment: .leading, spacing: 14) {
                Text("ELİNİZİN ALTINDA").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                shortcut("Yeni proje", keys: "⌘N")
                shortcut("Proje aç", keys: "⌘O")
                shortcut("Kaydet", keys: "⌘S")
            }.foregroundStyle(Theme.secondary)
            Divider().padding(.vertical, 24)
            Text("Size ait bir kurgu alanı.").font(.caption).foregroundStyle(Theme.ink)
            Text("Hesap gerekmez.\nGonavi 0.3 · Teknik önizleme")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(5).padding(.top, 7)
        }.padding(24).frame(maxHeight: .infinity, alignment: .top).background(Theme.panel)
    }

    private var continueRow: some View {
        HStack(spacing: 14) {
            Image(systemName: store.hasOpenProject ? "play.circle" : "arrow.clockwise.circle")
                .font(.system(size: 26, weight: .light)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(store.hasOpenProject ? store.project.name : "Önceki oturumunuz hazır").fontWeight(.medium)
                Text(store.hasOpenProject ? "Açık projeniz korunuyor. Kaldığınız yerden devam edin." : "Otomatik kaydedilen çalışmanızı kurtarabilirsiniz.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button(store.hasOpenProject ? "Devam et" : "Oturumu kurtar", action: store.resumeProject)
                .buttonStyle(.bordered)
        }.padding(18).background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private func recentRow(_ recent: RecentProject) -> some View {
        Button { store.openRecent(recent) } label: {
            HStack(spacing: 16) {
                SceneGlyph(preset: recent.scene, selected: false).frame(width: 40, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(recent.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text("\(recent.scene.rawValue)  ·  \(duration(recent.duration.seconds))  ·  \(URL(fileURLWithPath: recent.path).deletingLastPathComponent().lastPathComponent)")
                        .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer()
                Text(recent.openedAt, style: .relative).font(.caption).foregroundStyle(Theme.secondary)
                Image(systemName: "arrow.up.right").foregroundStyle(Theme.secondary)
            }.padding(18).contentShape(Rectangle())
        }.buttonStyle(.plain).help(recent.path)
            .contextMenu { Button("Geçmişten Kaldır") { store.removeRecent(recent) } }
    }
    private func shortcut(_ title: String, keys: String) -> some View {
        HStack { Text(title); Spacer(); Text(keys).font(.system(size: 11, design: .monospaced)) }.font(.caption)
    }
    private func duration(_ seconds: Double) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
    private var architecture: String {
        #if arch(x86_64)
        "Intel"
        #else
        "Apple Silicon"
        #endif
    }
}

struct SceneGlyph: View {
    let preset: ScenePreset
    let selected: Bool
    var body: some View {
        GeometryReader { geometry in
            let ratio = CGFloat(preset.width) / CGFloat(preset.height)
            let height = min(geometry.size.height, geometry.size.width / ratio)
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? Theme.accent.opacity(0.09) : Theme.inset)
                .overlay {
                    RoundedRectangle(cornerRadius: 4).stroke(selected ? Theme.accent : Theme.secondary.opacity(0.4), lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "play.fill").font(.system(size: max(8, height * 0.17), weight: .light))
                        .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                }
                .frame(width: height * ratio, height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct NewProjectView: View {
    @ObservedObject var store: EditorStore
    @State private var name = ""
    @State private var scene = ScenePreset.portrait
    @State private var fps = 30
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Yeni proje").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("İlk karenizin boyutunu seçin. Bunları sonra da değiştirebilirsiniz.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { store.creatingProject = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Kapat").keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("PROJE ADI").font(.system(size: 10, weight: .semibold)).tracking(1)
                TextField("Örneğin: Hafta sonu günlüğü", text: $name)
                    .textFieldStyle(.roundedBorder).controlSize(.large).focused($nameFocused)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("SAHNE ORANI").font(.system(size: 10, weight: .semibold)).tracking(1)
                HStack(spacing: 12) {
                    ForEach(ScenePreset.allCases, id: \.self) { preset in
                        Button { scene = preset } label: {
                            VStack(spacing: 12) {
                                SceneGlyph(preset: preset, selected: scene == preset).frame(height: 55)
                                Text(preset.rawValue).font(.system(size: 13, weight: .semibold))
                                Text(label(preset)).font(.caption2).foregroundStyle(Theme.secondary)
                            }.padding(16).frame(maxWidth: .infinity)
                                .background(scene == preset ? Theme.accent.opacity(0.06) : Theme.inset, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(scene == preset ? Theme.accent : Theme.rule, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel("\(preset.rawValue), \(label(preset))")
                            .accessibilityAddTraits(scene == preset ? [.isSelected] : [])
                    }
                }
            }
            HStack {
                Text("Kare hızı").font(.callout)
                Picker("Kare hızı", selection: $fps) {
                    ForEach([24, 25, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
                }.labelsHidden().frame(width: 112)
                Spacer()
                Text("\(scene.width) × \(scene.height) piksel").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            Divider()
            HStack {
                Text("Videoları bir sonraki adımda ekleyin.").font(.caption).foregroundStyle(Theme.secondary)
                Spacer()
                Button("Projeyi oluştur") { store.createProject(name: name, scene: scene, fps: fps) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.onAccent)
                    .controlSize(.large).keyboardShortcut(.defaultAction)
                    .disabled(name.count > 120)
            }
        }.padding(32).frame(width: 650).background(Theme.panel)
            .onAppear { nameFocused = true }
    }
    private func label(_ preset: ScenePreset) -> String {
        switch preset { case .portrait: "Dikey"; case .landscape: "Yatay"; case .square: "Kare"; case .social: "Sosyal" }
    }
}

struct WorkspaceActionStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primary ? Theme.onAccent : Theme.ink)
            .background(primary ? Theme.accent : Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(primary ? Theme.accent : Theme.rule, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

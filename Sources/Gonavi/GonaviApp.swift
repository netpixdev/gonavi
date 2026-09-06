import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: EditorStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        return store.confirmDiscard() ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct GonaviApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = EditorStore()
    var body: some Scene {
        Window("Gonavi", id: "editor") {
            WorkspaceView(store: store)
                .onAppear { delegate.store = store }
                .frame(minWidth: 1040, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni Proje", action: store.newProject).keyboardShortcut("n").disabled(!store.editable)
                Button("Proje Aç…", action: store.open).keyboardShortcut("o").disabled(!store.editable)
                Button("Medya Ekle…", action: store.chooseMedia).keyboardShortcut("i").disabled(!store.editable)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Kaydet") { store.save() }.keyboardShortcut("s").disabled(!store.hasOpenProject)
                Button("Farklı Kaydet…") { store.save(asNew: true) }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(!store.hasOpenProject)
                Button("Dışa Aktar…", action: store.exportVideo).keyboardShortcut("e").disabled(!store.canExport)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Geri Al", action: store.undo).keyboardShortcut("z").disabled(!store.canUndo || !store.editable)
                Button("Yinele", action: store.redo).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!store.canRedo || !store.editable)
            }
            CommandMenu("Kurgu") {
                Button("Sessizlikleri Temizle…", action: store.automaticSilences)
                    .disabled(store.project.clips.isEmpty || !store.editable)
                Button("Otomatik Altyazı…", action: store.automaticCaptions)
                    .disabled(store.project.clips.isEmpty || !store.editable)
            }
        }
    }
}

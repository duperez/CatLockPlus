//
//  CatLockPlus — trava teclado, mouse/trackpad e Touch Bar
//  Travar:    botão 🔒 na Control Strip (Touch Bar) ou Ctrl+L
//  Destravar: Ctrl+L
//

import AppKit
import ApplicationServices
import Darwin

// MARK: - APIs privadas da Touch Bar (DFRFoundation), carregadas via dlopen como o TouchBarHelper faz

enum TouchBarPrivate {

    private static let dfrPath = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"

    private typealias SetPresenceFn = @convention(c) (NSString, Bool) -> Void
    private typealias ShowsCloseBoxFn = @convention(c) (Bool) -> Void

    private static let setPresence: SetPresenceFn? = {
        guard let h = dlopen(dfrPath, RTLD_LAZY) else {
            NSLog("CatLockPlus: ERRO dlopen DFRFoundation: %s", dlerror())
            return nil
        }
        guard let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") else {
            NSLog("CatLockPlus: símbolo DFRElementSetControlStripPresenceForIdentifier NÃO existe")
            return nil
        }
        return unsafeBitCast(sym, to: SetPresenceFn.self)
    }()

    private static let showsCloseBox: ShowsCloseBoxFn? = {
        guard let h = dlopen(dfrPath, RTLD_LAZY),
              let sym = dlsym(h, "DFRSystemModalShowsCloseBoxWhenFrontMost") else {
            NSLog("CatLockPlus: símbolo DFRSystemModalShowsCloseBoxWhenFrontMost NÃO existe")
            return nil
        }
        return unsafeBitCast(sym, to: ShowsCloseBoxFn.self)
    }()

    // Loga a disponibilidade de cada API privada — rode pelo Terminal para ver
    static func logDiagnostics() {
        NSLog("CatLockPlus: DFRElementSetControlStripPresenceForIdentifier: %@", setPresence != nil ? "OK" : "AUSENTE")
        NSLog("CatLockPlus: DFRSystemModalShowsCloseBoxWhenFrontMost: %@", showsCloseBox != nil ? "OK" : "AUSENTE")
        let itemSels = ["addSystemTrayItem:", "removeSystemTrayItem:"]
        for s in itemSels {
            let ok = class_getClassMethod(NSTouchBarItem.self, Selector(s)) != nil
            NSLog("CatLockPlus: +[NSTouchBarItem %@]: %@", s, ok ? "OK" : "AUSENTE")
        }
        let barSels = [
            "presentSystemModalTouchBar:systemTrayItemIdentifier:",
            "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:",
            "dismissSystemModalTouchBar:",
            "minimizeSystemModalTouchBar:",
        ]
        for s in barSels {
            let ok = class_getClassMethod(NSTouchBar.self, Selector(s)) != nil
            NSLog("CatLockPlus: +[NSTouchBar %@]: %@", s, ok ? "OK" : "AUSENTE")
        }
    }

    static func addSystemTrayItem(_ item: NSTouchBarItem) {
        let sel = Selector(("addSystemTrayItem:"))
        guard let m = class_getClassMethod(NSTouchBarItem.self, sel) else {
            NSLog("CatLockPlus: ERRO — addSystemTrayItem: não existe nesta versão do macOS")
            return
        }
        typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void
        let fn = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        fn(NSTouchBarItem.self, sel, item)
        NSLog("CatLockPlus: addSystemTrayItem chamado")

        if let setPresence = setPresence {
            setPresence(item.identifier.rawValue as NSString, true)
            NSLog("CatLockPlus: setControlStripPresence(true) chamado")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                setPresence(item.identifier.rawValue as NSString, true)
            }
        }
    }

    static func presentSystemModal(_ touchBar: NSTouchBar, systemTrayItemIdentifier id: String?) {
        showsCloseBox?(false)

        // Variante com placement (a que o Pock usa; placement=1 cobre a barra inteira)
        let sel3 = Selector(("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"))
        if let m = class_getClassMethod(NSTouchBar.self, sel3) {
            typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar?, CLongLong, NSString?) -> Void
            let fn = unsafeBitCast(method_getImplementation(m), to: Fn.self)
            fn(NSTouchBar.self, sel3, touchBar, 1, id as NSString?)
            NSLog("CatLockPlus: modal apresentado (variante placement)")
            return
        }

        let sel2 = Selector(("presentSystemModalTouchBar:systemTrayItemIdentifier:"))
        if let m = class_getClassMethod(NSTouchBar.self, sel2) {
            typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar?, NSString?) -> Void
            let fn = unsafeBitCast(method_getImplementation(m), to: Fn.self)
            fn(NSTouchBar.self, sel2, touchBar, id as NSString?)
            NSLog("CatLockPlus: modal apresentado (variante 2 argumentos)")
            return
        }

        NSLog("CatLockPlus: ERRO — nenhuma variante de presentSystemModalTouchBar existe")
    }

    static func dismissSystemModal(_ touchBar: NSTouchBar) {
        let sel = Selector(("dismissSystemModalTouchBar:"))
        guard let m = class_getClassMethod(NSTouchBar.self, sel) else {
            NSLog("CatLockPlus: ERRO — dismissSystemModalTouchBar: não existe")
            return
        }
        typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar?) -> Void
        let fn = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        fn(NSTouchBar.self, sel, touchBar)
    }
}

// MARK: - Atalho configurável

struct Shortcut {
    var keyCode: Int64
    var modifiers: CGEventFlags
    var label: String

    static let `default` = Shortcut(keyCode: 37, modifiers: .maskControl, label: "⌃L")

    private static let mainMods: [CGEventFlags] = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    /// Compara keycode e o conjunto exato de modificadores principais
    func matches(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == keyCode else { return false }
        let flags = event.flags
        for m in Self.mainMods where modifiers.contains(m) != flags.contains(m) {
            return false
        }
        return true
    }

    static func load() -> Shortcut {
        let d = UserDefaults.standard
        guard d.object(forKey: "shortcutKeyCode") != nil else { return .default }
        return Shortcut(
            keyCode: Int64(d.integer(forKey: "shortcutKeyCode")),
            modifiers: CGEventFlags(rawValue: UInt64(d.integer(forKey: "shortcutModifiers"))),
            label: d.string(forKey: "shortcutLabel") ?? "?"
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(Int(keyCode), forKey: "shortcutKeyCode")
        d.set(Int(modifiers.rawValue), forKey: "shortcutModifiers")
        d.set(label, forKey: "shortcutLabel")
    }
}

// MARK: - Controlador principal

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var lockedTouchBar: NSTouchBar?
    private var trayItem: NSCustomTouchBarItem?   // referência forte: sem ela o botão some da Touch Bar
    private(set) var isLocked = false

    private let trayItemID = "app.catlockplus.tray"
    private let lockedLabelID = NSTouchBarItem.Identifier("app.catlockplus.lockedLabel")

    // Atalho configurável (Preferências)
    private var shortcut = Shortcut.load()
    private var isRecording = false
    private var recordMonitor: Any?
    private var prefsWindow: NSWindow?
    private var recordButton: NSButton?
    private var lockMenuItem: NSMenuItem?

    // MARK: Ciclo de vida

    func applicationDidFinishLaunching(_ notification: Notification) {
        TouchBarPrivate.logDiagnostics()
        setupStatusItem()
        setupControlStripButton()
        ensureAccessibilityThenStartTap()

        // Modo de teste: CATLOCK_TBTEST=1 mostra a faixa "Travado" por 5s sem travar nada
        if ProcessInfo.processInfo.environment["CATLOCK_TBTEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSLog("CatLockPlus: TESTE — apresentando Touch Bar modal por 5s")
                self.presentLockedTouchBar()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    if let bar = self.lockedTouchBar {
                        TouchBarPrivate.dismissSystemModal(bar)
                        self.lockedTouchBar = nil
                    }
                    NSLog("CatLockPlus: TESTE — modal dispensado")
                }
            }
        }
    }

    // MARK: Barra de menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"

        let menu = NSMenu()
        let lockItem = NSMenuItem(title: "Travar agora — \(shortcut.label)", action: #selector(lockNow), keyEquivalent: "")
        lockItem.target = self
        menu.addItem(lockItem)
        lockMenuItem = lockItem
        let prefsItem = NSMenuItem(title: "Preferências…", action: #selector(openPrefs), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    // MARK: Preferências

    @objc private func openPrefs() {
        if prefsWindow == nil { buildPrefsWindow() }
        prefsWindow?.center()
        prefsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildPrefsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Preferências do CatLockPlus"
        window.isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 170))

        let title = NSTextField(labelWithString: "Atalho para travar / destravar:")
        title.frame = NSRect(x: 20, y: 125, width: 360, height: 20)
        content.addSubview(title)

        let button = NSButton(title: shortcut.label, target: self, action: #selector(startRecording))
        button.frame = NSRect(x: 20, y: 85, width: 220, height: 32)
        button.bezelStyle = .rounded
        content.addSubview(button)
        recordButton = button

        let reset = NSButton(title: "Restaurar padrão (⌃L)", target: self, action: #selector(resetShortcut))
        reset.frame = NSRect(x: 250, y: 85, width: 130, height: 32)
        reset.bezelStyle = .rounded
        reset.font = NSFont.systemFont(ofSize: 11)
        content.addSubview(reset)

        let hint = NSTextField(wrappingLabelWithString:
            "Clique no botão e pressione a nova combinação (Esc cancela). Use pelo menos Ctrl, Option ou Command para o gato não travar sozinho.")
        hint.frame = NSRect(x: 20, y: 15, width: 360, height: 60)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        content.addSubview(hint)

        window.contentView = content
        prefsWindow = window
    }

    @objc private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        recordButton?.title = "Pressione a combinação…"
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecorded(event)
            return nil   // engole o evento; não dispara ações do app
        }
    }

    private func stopRecording() {
        if let m = recordMonitor { NSEvent.removeMonitor(m); recordMonitor = nil }
        isRecording = false
        refreshShortcutUI()
    }

    private func handleRecorded(_ event: NSEvent) {
        let mods = event.modifierFlags
        // Esc puro cancela
        if event.keyCode == 53 && mods.intersection([.control, .option, .command]).isEmpty {
            stopRecording()
            return
        }
        var cg: CGEventFlags = []
        if mods.contains(.control) { cg.insert(.maskControl) }
        if mods.contains(.option)  { cg.insert(.maskAlternate) }
        if mods.contains(.shift)   { cg.insert(.maskShift) }
        if mods.contains(.command) { cg.insert(.maskCommand) }

        // Exige um modificador "forte" — shift sozinho ou tecla pura seriam fáceis de acionar por acidente
        guard !cg.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty else {
            stopRecording()
            let a = NSAlert()
            a.messageText = "Combinação muito fácil de acionar sem querer"
            a.informativeText = "Use pelo menos Ctrl, Option ou Command junto com a tecla."
            a.runModal()
            return
        }

        shortcut = Shortcut(keyCode: Int64(event.keyCode), modifiers: cg,
                            label: Self.modifierSymbols(cg) + Self.keyName(event))
        shortcut.save()
        stopRecording()
    }

    @objc private func resetShortcut() {
        shortcut = .default
        shortcut.save()
        refreshShortcutUI()
    }

    private func refreshShortcutUI() {
        recordButton?.title = shortcut.label
        lockMenuItem?.title = "Travar agora — \(shortcut.label)"
    }

    private static func modifierSymbols(_ f: CGEventFlags) -> String {
        var s = ""
        if f.contains(.maskControl)   { s += "⌃" }
        if f.contains(.maskAlternate) { s += "⌥" }
        if f.contains(.maskShift)     { s += "⇧" }
        if f.contains(.maskCommand)   { s += "⌘" }
        return s
    }

    private static func keyName(_ event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Espaço", 51: "⌫", 53: "Esc", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = special[event.keyCode] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "tecla \(event.keyCode)"
    }

    // MARK: Botão na Control Strip (Touch Bar)

    private func setupControlStripButton() {
        let item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(trayItemID))
        let button = NSButton(title: "🔒🐱", target: self, action: #selector(lockNow))
        item.view = button
        trayItem = item   // mantém o item vivo — sem isso ele é desalocado e some
        TouchBarPrivate.addSystemTrayItem(item)
    }

    // MARK: Permissão de Acessibilidade + Event Tap

    private func ensureAccessibilityThenStartTap() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) {
            startEventTap()
        } else {
            // Aguarda o usuário conceder a permissão em Ajustes do Sistema
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.startEventTap()
                }
            }
        }
    }

    private func startEventTap() {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .mouseMoved, .scrollWheel,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        ]
        var mask: CGEventMask = 0
        for t in types { mask |= CGEventMask(1) << CGEventMask(t.rawValue) }
        // NX_SYSDEFINED (14): teclas de mídia/brilho/volume, inclusive vindas da Touch Bar
        mask |= CGEventMask(1) << 14
        // Gestos do trackpad (29–34)
        for raw in 29...34 { mask |= CGEventMask(1) << CGEventMask(raw) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else {
            let alert = NSAlert()
            alert.messageText = "Não foi possível criar o interceptador de eventos"
            alert.informativeText = "Verifique se o CatLockPlus tem permissão em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade, e abra o app de novo."
            alert.runModal()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Se o macOS desativar o tap (timeout), reativa
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Atalho configurável alterna travar/destravar (ignorado enquanto grava atalho novo)
        if type == .keyDown, !isRecording, shortcut.matches(event) {
            DispatchQueue.main.async { self.toggleLock() }
            return nil
        }

        // Travado: engole tudo (teclado, mouse, trackpad, teclas da Touch Bar)
        if isLocked { return nil }

        return Unmanaged.passUnretained(event)
    }

    // MARK: Travar / destravar

    @objc func lockNow() {
        if !isLocked { toggleLock() }
    }

    func toggleLock() {
        isLocked ? unlock() : lock()
    }

    private func lock() {
        guard eventTap != nil else {
            let alert = NSAlert()
            alert.messageText = "Ainda sem permissão de Acessibilidade"
            alert.informativeText = "Conceda a permissão em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade antes de travar."
            alert.runModal()
            return
        }
        isLocked = true
        statusItem.button?.title = "🔒"
        presentLockedTouchBar()
    }

    private func unlock() {
        isLocked = false
        statusItem.button?.title = "🐱"
        if let bar = lockedTouchBar {
            TouchBarPrivate.dismissSystemModal(bar)
            lockedTouchBar = nil
        }
    }

    // Touch Bar modal que cobre tudo enquanto travado (toques não fazem nada)
    private func presentLockedTouchBar() {
        let bar = NSTouchBar()
        let item = NSCustomTouchBarItem(identifier: lockedLabelID)
        let label = NSTextField(labelWithString: "🔒 Travado pelo CatLockPlus — pressione \(shortcut.label) para destravar")
        label.alignment = .center
        item.view = label
        bar.templateItems = [item]
        bar.defaultItemIdentifiers = [lockedLabelID]
        lockedTouchBar = bar
        TouchBarPrivate.presentSystemModal(bar, systemTrayItemIdentifier: trayItemID)
    }
}

// MARK: - Entrada

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = DictationController()
    private let floatingButtonWindowController = FloatingButtonWindowController()
    private let globalHotKey = GlobalHotKey()
    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var composeItem: NSMenuItem?
    private var autoPasteItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLogger.clear()
        DebugLogger.log("applicationDidFinishLaunching bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")

        guard ensureSingleInstance() else {
            DebugLogger.log("terminating duplicate instance")
            NSApplication.shared.terminate(nil)
            return
        }

        controller.stateDidChange = { [weak self] in
            self?.refreshMenuState()
        }

        floatingButtonWindowController.onStartMode = { [weak self] mode in
            Task { @MainActor in
                await self?.controller.startDictation(mode: mode)
            }
        }

        floatingButtonWindowController.onStop = { [weak self] in
            Task { @MainActor in
                await self?.controller.stopCurrentDictation()
            }
        }

        setupStatusItem()
        floatingButtonWindowController.showFloatingButton()
        registerGlobalHotKey()
        refreshMenuState()
        DebugLogger.log("application finished launch")
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKey.unregister()
        DebugLogger.log("applicationWillTerminate")
    }

    private func registerGlobalHotKey() {
        do {
            try globalHotKey.register([
                // Ctrl+Opt+D: Dictate.
                GlobalHotKeyRegistration(
                    id: 1,
                    keyCode: UInt32(kVK_ANSI_D),
                    modifiers: UInt32(controlKey | optionKey)
                ) { [weak self] in
                    Task { @MainActor in
                        await self?.handleShortcut(mode: .dictate)
                    }
                },
                // Ctrl+Opt+C: Compose.
                GlobalHotKeyRegistration(
                    id: 2,
                    keyCode: UInt32(kVK_ANSI_C),
                    modifiers: UInt32(controlKey | optionKey)
                ) { [weak self] in
                    Task { @MainActor in
                        await self?.handleShortcut(mode: .compose)
                    }
                }
            ])
            DebugLogger.log("globalHotKeys registered dictate=ctrl+opt+d compose=ctrl+opt+c")
        } catch {
            DebugLogger.log("globalHotKey register failed error=\(error.localizedDescription)")
        }
    }

    private func handleShortcut(mode: DictationMode) async {
        if controller.isRecording {
            await controller.stopCurrentDictation()
        } else {
            await controller.startDictation(mode: mode)
        }
    }

    private func ensureSingleInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "Wisp")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Start Dictate  ^⌥D", action: #selector(startDictateFromMenu), keyEquivalent: "")
        toggleItem?.target = self
        composeItem = NSMenuItem(title: "Start Compose  ^⌥C", action: #selector(startComposeFromMenu), keyEquivalent: "")
        composeItem?.target = self
        autoPasteItem = NSMenuItem(title: "Insert Result Into Current App", action: #selector(toggleAutoPaste), keyEquivalent: "")
        autoPasteItem?.target = self

        let copyItem = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLastTranscript), keyEquivalent: "")
        copyItem.target = self

        let pasteItem = NSMenuItem(title: "Paste Last Transcript", action: #selector(pasteLastTranscript), keyEquivalent: "")
        pasteItem.target = self

        let permissionsItem = NSMenuItem(title: "Prompt Accessibility Permission", action: #selector(promptAccessibilityPermission), keyEquivalent: "")
        permissionsItem.target = self

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self

        if let toggleItem {
            menu.addItem(toggleItem)
        }

        if let composeItem {
            menu.addItem(composeItem)
        }

        if let autoPasteItem {
            menu.addItem(autoPasteItem)
        }

        menu.addItem(.separator())
        menu.addItem(copyItem)
        menu.addItem(pasteItem)
        menu.addItem(permissionsItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Click the floating bubble to choose Dictate or Compose",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Drag the bubble to move it anywhere",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func refreshMenuState() {
        if controller.isRecording {
            toggleItem?.title = "Stop \(controller.currentMode.title)"
            composeItem?.isEnabled = false
        } else {
            toggleItem?.title = "Start Dictate  ^⌥D"
            composeItem?.isEnabled = !controller.isTranscribing
        }

        toggleItem?.isEnabled = !controller.isTranscribing || controller.isRecording
        autoPasteItem?.state = controller.autoPasteEnabled ? .on : .off

        let symbolName: String

        if controller.isRecording {
            symbolName = "waveform.circle.fill"
        } else if controller.isTranscribing {
            symbolName = "hourglass.circle"
        } else {
            symbolName = "mic.circle"
        }

        statusItem?.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Wisp"
        )
        floatingButtonWindowController.update(
            isRecording: controller.isRecording,
            isTranscribing: controller.isTranscribing,
            statusMessage: controller.statusMessage
        )
    }

    @objc private func startDictateFromMenu() {
        Task { @MainActor in
            if controller.isRecording {
                await controller.stopCurrentDictation()
            } else {
                await controller.startDictation(mode: .dictate)
            }
        }
    }

    @objc private func startComposeFromMenu() {
        Task { @MainActor in
            await controller.startDictation(mode: .compose)
        }
    }

    @objc private func toggleAutoPaste() {
        controller.toggleAutoPaste()
    }

    @objc private func copyLastTranscript() {
        controller.copyTranscriptToClipboard()
    }

    @objc private func pasteLastTranscript() {
        Task { @MainActor in
            await controller.pasteTranscriptIntoFrontmostApp()
        }
    }

    @objc private func promptAccessibilityPermission() {
        AccessibilityService.promptForPermission()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

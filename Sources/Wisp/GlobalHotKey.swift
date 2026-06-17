import Carbon
import Foundation

enum GlobalHotKeyError: LocalizedError {
    case installHandlerFailed(OSStatus)
    case registerFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandlerFailed(let status):
            return "InstallEventHandler failed with status \(status)."
        case .registerFailed(let status):
            return "RegisterEventHotKey failed with status \(status)."
        }
    }
}

struct GlobalHotKeyRegistration {
    let id: UInt32
    let keyCode: UInt32
    let modifiers: UInt32
    let onKeyPress: () -> Void
}

final class GlobalHotKey {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var handlers: [UInt32: () -> Void] = [:]

    func register(keyCode: UInt32, modifiers: UInt32, onKeyPress: @escaping () -> Void) throws {
        try register([
            GlobalHotKeyRegistration(id: 1, keyCode: keyCode, modifiers: modifiers, onKeyPress: onKeyPress)
        ])
    }

    func register(_ registrations: [GlobalHotKeyRegistration]) throws {
        unregister()
        handlers = Dictionary(uniqueKeysWithValues: registrations.map { ($0.id, $0.onKeyPress) })

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else {
                    return noErr
                }

                hotKey.handleKeyPress(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw GlobalHotKeyError.installHandlerFailed(installStatus)
        }

        for registration in registrations {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x56545458), id: registration.id)
            let registerStatus = RegisterEventHotKey(
                registration.keyCode,
                registration.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            guard registerStatus == noErr else {
                throw GlobalHotKeyError.registerFailed(registerStatus)
            }

            if let hotKeyRef {
                hotKeyRefs.append(hotKeyRef)
            }
        }
    }

    func unregister() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }

        hotKeyRefs = []
        eventHandlerRef = nil
        handlers = [:]
    }

    private func handleKeyPress(id: UInt32) {
        handlers[id]?()
    }
}

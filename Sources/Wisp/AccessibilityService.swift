import ApplicationServices
import CoreGraphics

@MainActor
struct AccessibilityService {
    typealias FocusedTextElement = AXUIElement

    func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func promptForPermission() {
        _ = AccessibilityService().isTrusted(prompt: true)
    }

    func captureFocusedTextElement() -> FocusedTextElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(focusedValue, to: AXUIElement.self)
    }

    func insertText(_ text: String, into element: FocusedTextElement) -> Bool {
        guard !text.isEmpty else {
            return true
        }

        guard let currentValue = stringValue(of: element) else {
            return false
        }

        let selectedRange = selectedTextRange(of: element) ?? CFRange(location: currentValue.utf16.count, length: 0)
        let currentNSString = currentValue as NSString
        let safeLocation = max(0, min(selectedRange.location, currentNSString.length))
        let safeLength = max(0, min(selectedRange.length, currentNSString.length - safeLocation))
        let replacementRange = NSRange(location: safeLocation, length: safeLength)
        let updatedValue = currentNSString.replacingCharacters(in: replacementRange, with: text)

        let setValueStatus = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            updatedValue as CFTypeRef
        )

        guard setValueStatus == .success else {
            return false
        }

        let insertionLocation = safeLocation + (text as NSString).length
        let insertionRange = CFRange(location: insertionLocation, length: 0)
        _ = setSelectedTextRange(insertionRange, for: element)
        return true
    }

    func simulatePaste() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        let keyCodeForV: CGKeyCode = 9
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    func simulateBackspace(count: Int) -> Bool {
        guard count > 0, let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        let keyCodeForDelete: CGKeyCode = 51
        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForDelete, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForDelete, keyDown: false) else {
                return false
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }

    private func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }

        return value as? String
    }

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
        let axValue = value,
        CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let selectedRangeValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(selectedRangeValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(selectedRangeValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private func setSelectedTextRange(_ range: CFRange, for element: AXUIElement) -> Bool {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        ) == .success
    }
}

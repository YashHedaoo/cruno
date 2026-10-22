import AppKit
import CoreGraphics
import Foundation

// MARK: - Mouse & Keyboard Simulation for GUI Computer Use (Phase 3)

@MainActor
final class MouseKeyboardSimulator {
    static let shared = MouseKeyboardSimulator()

    var isCancelled: Bool = false

    private init() {}

    /// Performs a left, right, or double click at specified screen coordinates.
    func click(at point: CGPoint, button: String = "left", count: Int = 1) -> String {
        guard !isCancelled else { return "Action cancelled." }

        let isRight = button.lowercased() == "right"
        let downType: CGEventType = isRight ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = isRight ? .rightMouseUp : .leftMouseUp
        let mouseButton: CGMouseButton = isRight ? .right : .left

        // First move mouse to target coordinate smoothly
        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }
        usleep(20_000) // 20ms pause

        for i in 1...max(1, count) {
            guard !isCancelled else { break }
            guard let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: mouseButton),
                  let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: mouseButton) else {
                return "Failed to create mouse event."
            }
            down.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(i))

            down.post(tap: .cghidEventTap)
            usleep(25_000)
            up.post(tap: .cghidEventTap)
            if i < count { usleep(60_000) }
        }

        return "Clicked at (\(Int(point.x)), \(Int(point.y))) with \(button) click (count: \(count))."
    }

    /// Moves the mouse cursor to specific coordinates without clicking.
    func move(to point: CGPoint) -> String {
        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            return "Failed to move mouse."
        }
        move.post(tap: .cghidEventTap)
        return "Moved mouse to (\(Int(point.x)), \(Int(point.y)))."
    }

    /// Scrolls the screen up or down.
    func scroll(direction: String, amount: Int) -> String {
        let delta = direction.lowercased() == "up" ? Int32(amount) : -Int32(amount)
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else {
            return "Failed to create scroll event."
        }
        event.post(tap: .cghidEventTap)
        return "Scrolled \(direction) by \(amount) lines."
    }

    /// Types unicode text into the currently active element.
    func typeText(_ text: String) -> String {
        guard !isCancelled else { return "Action cancelled." }

        for char in text {
            guard !isCancelled else { break }
            let utf16Chars = Array(String(char).utf16)
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { continue }
            down.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            up.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            down.post(tap: .cghidEventTap)
            usleep(12_000)
            up.post(tap: .cghidEventTap)
            usleep(12_000)
        }
        return "Typed: \"\(text)\""
    }

    /// Presses a hotkey with optional modifiers (e.g. Cmd+C, Cmd+V, Enter, Escape, Tab).
    func pressKey(key: String, modifiers: [String]) -> String {
        let keyCode: CGKeyCode
        switch key.lowercased() {
        case "return", "enter": keyCode = 36
        case "tab":            keyCode = 48
        case "space":          keyCode = 49
        case "delete", "backspace": keyCode = 51
        case "escape", "esc":  keyCode = 53
        case "up":             keyCode = 126
        case "down":           keyCode = 125
        case "left":           keyCode = 123
        case "right":          keyCode = 124
        case "a": keyCode = 0
        case "c": keyCode = 8
        case "v": keyCode = 9
        case "x": keyCode = 7
        case "z": keyCode = 6
        case "w": keyCode = 13
        case "r": keyCode = 15
        default: keyCode = 36
        }

        var flags: CGEventFlags = []
        for mod in modifiers {
            switch mod.lowercased() {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift":          flags.insert(.maskShift)
            case "alt", "option":  flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: break
            }
        }

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return "Failed to press key."
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(25_000)
        up.post(tap: .cghidEventTap)

        let modStr = modifiers.isEmpty ? "" : modifiers.joined(separator: "+") + "+"
        return "Pressed \(modStr)\(key.capitalized)."
    }
}

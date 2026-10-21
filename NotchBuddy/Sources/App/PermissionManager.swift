import AppKit
import ApplicationServices
import Foundation

// MARK: - Live macOS Permissions & Automation Diagnostics (Phase 2)

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var hasAccessibility: Bool = false
    @Published var hasChromeAutomation: Bool = false
    @Published var hasScreenCapture: Bool = false
    @Published var selfTestReport: String? = nil
    @Published var isRunningSelfTest: Bool = false

    private init() {
        refreshPermissions()
    }

    // MARK: - Refresh

    func refreshPermissions() {
        hasAccessibility = checkAccessibility()
        hasChromeAutomation = checkChromeAutomation()
        hasScreenCapture = checkScreenCapture()
    }

    // MARK: - Accessibility

    func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        hasAccessibility = AXIsProcessTrusted()
    }

    // MARK: - Automation (Apple Events)

    func checkChromeAutomation() -> Bool {
        let script = "tell application \"Google Chrome\" to return name"
        var error: NSDictionary?
        let asScript = NSAppleScript(source: script)
        _ = asScript?.executeAndReturnError(&error)
        return error == nil
    }

    func requestChromeAutomation() {
        let script = "tell application \"Google Chrome\" to get count of windows"
        var error: NSDictionary?
        let asScript = NSAppleScript(source: script)
        _ = asScript?.executeAndReturnError(&error)
        hasChromeAutomation = (error == nil)
    }

    // MARK: - Screen Capture

    func checkScreenCapture() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    func requestScreenCapture() {
        if #available(macOS 10.15, *) {
            _ = CGRequestScreenCaptureAccess()
            hasScreenCapture = CGPreflightScreenCaptureAccess()
        }
    }

    // MARK: - System Preferences Deep Links

    enum PrivacyPane: String {
        case accessibility = "Privacy_Accessibility"
        case automation    = "Privacy_Automation"
        case screenCapture = "Privacy_ScreenCapture"
    }

    func openPrivacySettings(pane: PrivacyPane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Diagnostics Self-Test

    func runSelfTest() async {
        isRunningSelfTest = true
        selfTestReport = nil
        var lines: [String] = []

        // Test 1: Running applications
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        if !apps.isEmpty {
            lines.append("✓ Process Detection: Found \(apps.count) active apps (Finder, Chrome, etc.)")
        } else {
            lines.append("✕ Process Detection: Failed to enumerate active apps")
        }

        // Test 2: Clipboard read / write
        let original = NSPasteboard.general.string(forType: .string) ?? ""
        let testToken = "cruno_diag_\(Int(Date().timeIntervalSince1970))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(testToken, forType: .string)
        let readBack = NSPasteboard.general.string(forType: .string)
        if readBack == testToken {
            lines.append("✓ Clipboard Control: Read/write operational")
            NSPasteboard.general.clearContents()
            if !original.isEmpty {
                NSPasteboard.general.setString(original, forType: .string)
            }
        } else {
            lines.append("✕ Clipboard Control: Read/write failed")
        }

        // Test 3: AppleScript Automation
        let scriptTest = "return \"cruno_ok\""
        var err: NSDictionary?
        let res = NSAppleScript(source: scriptTest)?.executeAndReturnError(&err)
        if err == nil && res?.stringValue == "cruno_ok" {
            lines.append("✓ AppleScript Subsystem: Operational")
        } else {
            lines.append("✕ AppleScript Subsystem: Failed")
        }

        // Test 4: Google Chrome Scripting
        let chromeTest = SystemAutomationEngine.shared.runAppleScript("tell application \"Google Chrome\" to return name")
        if !chromeTest.hasPrefix("Error") {
            lines.append("✓ Google Chrome Automation: Authorized & Connected")
        } else {
            lines.append("! Google Chrome: Not currently open or authorization pending")
        }

        // Test 5: Accessibility Status
        let ax = AXIsProcessTrusted()
        lines.append(ax ? "✓ Accessibility API: Authorized" : "! Accessibility API: Pending authorization in System Settings")

        selfTestReport = lines.joined(separator: "\n")
        isRunningSelfTest = false
        refreshPermissions()
    }
}

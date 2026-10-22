import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

// MARK: - Screen & Window Vision Capture Engine (Phase 3)

@MainActor
final class ScreenCaptureEngine {
    static let shared = ScreenCaptureEngine()

    private init() {}

    /// Captures the main screen and returns downscaled JPEG image and base64 string.
    func captureMainScreen(maxDimension: CGFloat = 1440) async -> (image: NSImage, base64: String)? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                return captureViaCLI(windowID: nil, maxDimension: maxDimension)
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            config.showsCursor = true
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let nsImage = NSImage(cgImage: cgImage, size: CGSize(width: display.width, height: display.height))
            guard let jpegData = compressImage(nsImage, maxDimension: maxDimension) else { return nil }
            return (nsImage, jpegData.base64EncodedString())
        } catch {
            return captureViaCLI(windowID: nil, maxDimension: maxDimension)
        }
    }

    /// Captures the active frontmost application window.
    func captureFrontmostWindow(maxDimension: CGFloat = 1440) async -> (image: NSImage, base64: String)? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return await captureMainScreen(maxDimension: maxDimension)
        }
        let pid = frontApp.processIdentifier
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let window = content.windows.first(where: { $0.owningApplication?.processID == pid && $0.isOnScreen }) {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = Int(window.frame.width)
                config.height = Int(window.frame.height)
                config.showsCursor = true
                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let nsImage = NSImage(cgImage: cgImage, size: window.frame.size)
                guard let jpegData = compressImage(nsImage, maxDimension: maxDimension) else { return nil }
                return (nsImage, jpegData.base64EncodedString())
            }
        } catch {
            // fallback to CLI
        }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let appWindow = windowList.first { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        let windowID = appWindow?[kCGWindowNumber as String] as? CGWindowID
        if let cliResult = captureViaCLI(windowID: windowID, maxDimension: maxDimension) {
            return cliResult
        }
        return await captureMainScreen(maxDimension: maxDimension)
    }

    private func captureViaCLI(windowID: CGWindowID?, maxDimension: CGFloat) -> (image: NSImage, base64: String)? {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cruno_cap_\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        if let wid = windowID {
            process.arguments = ["-x", "-t", "jpg", "-l", "\(wid)", tempURL.path]
        } else {
            process.arguments = ["-x", "-m", "-t", "jpg", tempURL.path]
        }

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let image = NSImage(contentsOf: tempURL),
                  let jpegData = compressImage(image, maxDimension: maxDimension) else {
                return nil
            }
            return (image, jpegData.base64EncodedString())
        } catch {
            return nil
        }
    }

    private func compressImage(_ image: NSImage, maxDimension: CGFloat) -> Data? {
        var targetSize = image.size
        let maxSide = max(targetSize.width, targetSize.height)
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            targetSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        }

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }
}

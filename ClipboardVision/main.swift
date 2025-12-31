import AppKit
import GoogleGenerativeAI
import KeyboardShortcuts
import os

// Define the keyboard shortcut name.
extension KeyboardShortcuts.Name {
    static let triggerOCR = Self("triggerOCR")
    static let triggerCaptureOCR = Self("triggerCaptureOCR")
}

class OCRService {
    private let model: GenerativeModel

    init() {
        let config = GenerationConfig(
            temperature: 1,
            topP: 0.95,
            topK: 40,
            maxOutputTokens: 8192,
            responseMIMEType: "text/plain"
        )

        // Try to get API key from environment variable first.
        guard
            let geminiApiKey = ProcessInfo.processInfo.environment[
                "GEMINI_API_KEY"
            ]
                ?? Self.loadApiKeyFromConfig()
        else {
            fatalError("GEMINI_API_KEY not found in environment or config file")
        }

        self.model = GenerativeModel(
            name: "gemini-flash-latest",
            apiKey: geminiApiKey,
            generationConfig: config,
            systemInstruction:
                "You are to OCR an image and your response should contain just the result of this. No commentary or annotation."
        )
    }

    func performOCR(with image: NSImage) async throws -> String? {
        let response = try await model.generateContent("", image)
        return response.text
    }

    private static func loadApiKeyFromConfig() -> String? {
        let fileManager = FileManager.default

        // Get XDG_CONFIG_HOME or default to ~/.config
        let configBase =
            ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? NSString(string: "~/.config").expandingTildeInPath

        let configPath = (configBase as NSString).appendingPathComponent(
            "ClipboardVision/.env"
        )

        guard fileManager.fileExists(atPath: configPath),
            let contents = try? String(
                contentsOfFile: configPath,
                encoding: .utf8
            )
        else {
            return nil
        }

        // Parse the .env file looking for GEMINI_API_KEY
        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.split(separator: "=", maxSplits: 1).map(
                String.init
            )
            if parts.count == 2
                && parts[0].trimmingCharacters(in: .whitespaces)
                    == "GEMINI_API_KEY"
            {
                // trim quotes and whitespaces
                return parts[1].trimmingCharacters(in: .init(["'", "\"", " "]))
            }
        }
        return nil
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: "com.dkmar.ClipboardVision",
        category: "Utilities"
    )
    private let ocrService = OCRService()
    private let statusManager = StatusItemManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app to run as accessory (no dock icon)
        NSApplication.shared.setActivationPolicy(.accessory)
        setupKeyboardShortcuts()
    }

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .triggerOCR) { [weak self] in
            Task { await self?.handleShortcutPressed(captureMode: false) }
        }

        KeyboardShortcuts.onKeyUp(for: .triggerCaptureOCR) { [weak self] in
            Task { await self?.handleShortcutPressed(captureMode: true) }
        }

        if KeyboardShortcuts.getShortcut(for: .triggerOCR) == nil {
            KeyboardShortcuts.setShortcut(
                .init(.two, modifiers: [.command, .control, .shift]),
                for: .triggerOCR
            )
        }

        if KeyboardShortcuts.getShortcut(for: .triggerCaptureOCR) == nil {
            KeyboardShortcuts.setShortcut(
                .init(.five, modifiers: [.command, .control, .shift]),
                for: .triggerCaptureOCR
            )
        }
    }

    /// Handles the keyboard shortcut to trigger OCR.
    /// This function runs on the main actor so UI updates can be made directly.
    /// Specify 'captureMode' as True to capture a new screenshot; False to OCR the existing clipboard.
    @MainActor
    private func handleShortcutPressed(captureMode: Bool) async {
        // Show yellow indicator to signal processing start.
        statusManager.createStatusItem(color: .systemYellow)
        // status cleanup
        defer { statusManager.removeStatusItem() }

        var success = false
        do {
            var image: NSImage? = nil
            if captureMode {
                // Let user capture an image.
                let imagePath = "/tmp/_cbvision-image.png"

                let process = Process()
                process.executableURL = URL(
                    fileURLWithPath: "/usr/sbin/screencapture"
                )
                process.arguments = ["-i", imagePath]

                try process.run()
                process.waitUntilExit()
                image = NSImage(contentsOfFile: imagePath)
            } else {
                // Get image from clipboard.
                image =
                    NSPasteboard.general
                    .readObjects(forClasses: [NSImage.self], options: nil)?
                    .first as? NSImage
            }

            guard let image = image else {
                logger.error("No image found.")
                return
            }

            guard let text = try await ocrService.performOCR(with: image) else {
                logger.error("OCR failed.")
                return
            }

            // Success! Set clipboard and mark as successful
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            success = true

        } catch {
            logger.error("Error during process: \(error)")
        }

        // Set color once based on success/failure
        statusManager.createStatusItem(
            color: success ? .systemGreen : .systemRed
        )
        // persist status so user can see it
        try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
    }
}

// menubar icon
class StatusItemManager {
    private var statusItem: NSStatusItem?

    @MainActor
    func createStatusItem(color: NSColor) {
        // Remove any existing status item.
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }

        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let image = NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: "Status Indicator"
        ) {
            var config = NSImage.SymbolConfiguration(
                pointSize: 16,
                weight: .regular
            )
            config = config.applying(.init(hierarchicalColor: color))
            item.button?.image = image.withSymbolConfiguration(config)
        }

        statusItem = item
    }

    @MainActor
    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// run
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

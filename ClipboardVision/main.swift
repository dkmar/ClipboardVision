import AppKit
import GoogleGenerativeAI
import KeyboardShortcuts

// Define the keyboard shortcut name.
extension KeyboardShortcuts.Name {
   static let triggerOCR = Self("triggerOCR")
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
      let geminiApiKey =
         ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? Self.loadApiKeyFromConfig()
      guard !geminiApiKey.isEmpty else {
         fatalError("GEMINI_API_KEY not found in environment or config file")
      }

      self.model = GenerativeModel(
         name: "gemini-2.0-flash",
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

   private static func loadApiKeyFromConfig() -> String {
      let fileManager = FileManager.default

      // Get XDG_CONFIG_HOME or default to ~/.config
      let configBase =
         ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
         ?? NSString(string: "~/.config").expandingTildeInPath

      let configPath = (configBase as NSString).appendingPathComponent("ClipboardVision/.env")

      guard fileManager.fileExists(atPath: configPath),
         let contents = try? String(contentsOfFile: configPath, encoding: .utf8)
      else {
         return ""
      }

      // Parse the .env file looking for GEMINI_API_KEY
      let lines = contents.components(separatedBy: .newlines)
      for line in lines {
         let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
         if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "GEMINI_API_KEY" {
            return parts[1].trimmingCharacters(in: .whitespaces)
         }
      }

      return ""
   }
}

// main
class AppDelegate: NSObject, NSApplicationDelegate {
   private let ocrService = OCRService()
   private let statusManager = StatusItemManager()

   func applicationDidFinishLaunching(_ notification: Notification) {
      // Set app to run as accessory (no dock icon)
      NSApplication.shared.setActivationPolicy(.accessory)
      setupKeyboardShortcut()
   }

   private func setupKeyboardShortcut() {
      KeyboardShortcuts.onKeyUp(for: .triggerOCR) { [weak self] in
         Task { await self?.handleShortcutPressed() }
      }

      if KeyboardShortcuts.getShortcut(for: .triggerOCR) == nil {
         KeyboardShortcuts.setShortcut(
            .init(.five, modifiers: [.command, .control, .shift]),
            for: .triggerOCR
         )
      }
   }

   /// Handles the keyboard shortcut to trigger OCR.
   /// This function runs on the main actor so UI updates can be made directly.
   @MainActor
   private func handleShortcutPressed() async {
      // Show yellow indicator to signal processing start.
      statusManager.createStatusItem(color: .systemYellow)
      // status cleanup
      defer {
         statusManager.removeStatusItem()
      }

      // Get image from clipboard.
      if let image = NSPasteboard.general
         .readObjects(forClasses: [NSImage.self], options: nil)?
         .first as? NSImage
      {
         do {
            if let text = try await ocrService.performOCR(with: image) {
               // On success, set clipboard text.
               NSPasteboard.general.clearContents()
               NSPasteboard.general.setString(text, forType: .string)
               // Show green indicator for success.
               statusManager.createStatusItem(color: .systemGreen)
            } else {
               // No OCR text returned—show red indicator.
               statusManager.createStatusItem(color: .systemRed)
            }
         } catch {
            print("Error during OCR process: \(error)")
            // On exception, show red indicator.
            statusManager.createStatusItem(color: .systemRed)
         }
      } else {
         print("No image found in clipboard")
         // Show red indicator for error.
         statusManager.createStatusItem(color: .systemRed)
      }

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

      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      if let image = NSImage(
         systemSymbolName: "circle.fill", accessibilityDescription: "Status Indicator")
      {
         var config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
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

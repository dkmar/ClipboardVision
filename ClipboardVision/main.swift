import AppKit
import GoogleGenerativeAI
import KeyboardShortcuts

// Define the keyboard shortcut name
extension KeyboardShortcuts.Name {
   static let triggerOCR = Self("triggerOCR")
}

private func loadApiKeyFromConfig() -> String {
   let fileManager = FileManager.default
   
   // Get XDG_CONFIG_HOME or default to ~/.config
   let configBase = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
      ?? NSString(string: "~/.config").expandingTildeInPath
   
   let configPath = (configBase as NSString).appendingPathComponent("ClipboardVision/.env")
   
   guard fileManager.fileExists(atPath: configPath),
         let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
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

class AppDelegate: NSObject, NSApplicationDelegate {
   private var statusItem: NSStatusItem?
   private let model: GenerativeModel

   override init() {
      let config = GenerationConfig(
         temperature: 1,
         topP: 0.95,
         topK: 40,
         maxOutputTokens: 8192,
         responseMIMEType: "text/plain"
      )

      // Try to get API key from environment variable first
      let geminiApiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? loadApiKeyFromConfig()
      
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
      super.init()
   }

   

   func applicationDidFinishLaunching(_ notification: Notification) {
      // Set app to run as accessory (no dock icon)
      NSApplication.shared.setActivationPolicy(.accessory)

      // Register keyboard shortcut (ctrl+cmd+shift+5)
      KeyboardShortcuts.onKeyUp(for: .triggerOCR) { [weak self] in
         Task {
            await self?.handleShortcutPressed()
         }
      }

      // Set default keyboard shortcut if one isn't set already
      if KeyboardShortcuts.getShortcut(for: .triggerOCR) == nil {
         KeyboardShortcuts.setShortcut(
            .init(.five, modifiers: [.command, .control, .shift]),
            for: .triggerOCR
         )
      } else {
      }
   }

   // MARK: - UI Helpers (All on the Main Actor)

   /// Creates and returns a status item with a colored circular icon.
   @MainActor
   private func createStatusItem(color: NSColor) -> NSStatusItem {
      let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

      if let image = NSImage(
         systemSymbolName: "circle.fill", accessibilityDescription: "Status Indicator")
      {
         // Create a configuration with the desired size and color
         var config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
         config = config.applying(.init(hierarchicalColor: color))

         // Apply the configuration to the image
         statusItem.button?.image = image.withSymbolConfiguration(config)
      }

      return statusItem
   }

   /// Removes the current status item from the menu bar.
   @MainActor
   private func removeStatusItem() {
      if let item = statusItem {
         NSStatusBar.system.removeStatusItem(item)
         statusItem = nil
      }
   }

   // MARK: - Shortcut Handler

   /// Handles the keyboard shortcut to trigger OCR.
   /// This function runs on the main actor so UI updates can be made directly.
   @MainActor
   private func handleShortcutPressed() async {
      // Show red status indicator.
      statusItem = createStatusItem(color: .systemYellow)

      // Get image from clipboard.
      guard
         let image = NSPasteboard.general
            .readObjects(forClasses: [NSImage.self], options: nil)?
            .first as? NSImage
      else {
         print("No image found in clipboard")
         removeStatusItem()
         return
      }

      do {
         // Create Gemini request.
         let response = try await model.generateContent("", image)

         if let text = response.text {
            // Set clipboard to OCR text.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)

            // Show green status indicator.
            statusItem = createStatusItem(color: .systemGreen)

            // Wait 10 seconds before removing the indicator.
            try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            removeStatusItem()
         } else {
            removeStatusItem()
         }
      } catch {
         print("Error during OCR process: \(error)")
         removeStatusItem()
      }
   }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

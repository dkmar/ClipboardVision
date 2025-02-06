# ClipboardVision

ClipboardVision is a macOS utility that provides quick OCR (Optical Character Recognition) functionality for images in your clipboard using Google's Gemini AI model.

## Features

- Global keyboard shortcut (default: ⌃⌘⇧5) to trigger OCR
- Automatically replaces clipboard image with extracted text
- Visual status indicator showing process state
- Simple configuration via environment variables or config file

## Requirements

- macOS
- Google Gemini API key

## Installation
Download the [release](https://github.com/dkmar/ClipboardVision/releases/latest/download/ClipboardVision.zip)

## Setup
Set up your Gemini API key using one of these methods:
 - Set environment variable: `GEMINI_API_KEY=your_api_key`
 - Create a config file:
  ```bash
  mkdir -p ~/.config/ClipboardVision
  echo "GEMINI_API_KEY=your_api_key" > ~/.config/ClipboardVision/.env
  ```
  
## Usage

1. Copy an image containing text to your clipboard
2. Press ⌃⌘⇧5 (or your custom shortcut)
3. The menu bar icon will show:
   - Yellow: Processing
   - Green: Success (for 10 seconds)
4. The clipboard will now contain the extracted text

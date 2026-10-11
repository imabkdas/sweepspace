# SpaceSweep

A macOS disk-space analyzer built with Swift 6 and SwiftUI.

## Commands for new developers

- **Build ScannerCore**: `cd Packages/ScannerCore && swift build`
- **Run tests**: `cd Packages/ScannerCore && swift test`
- **Run benchmark CLI**: `cd Packages/ScannerCore && swift run scan-cli`

## Project Structure

- `SpaceSweep/` (Xcode App Target - Create this in Xcode)
- `Packages/ScannerCore/`: Local Swift Package handling file system scanning, data models, and segment queries.
- `docs/SPEC.md`: Product functional specification.
- `AGENTS.md`: Agent rules and shared briefs.

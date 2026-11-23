import AppKit
import Foundation

// Run explicitly from this directory: swift apply-folder-icons.swift [--dry-run]
let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let home = FileManager.default.homeDirectoryForCurrentUser
let mappings = [
    (folder: home.appendingPathComponent("dev", isDirectory: true), icon: "dev-folder.icns"),
    (folder: home.appendingPathComponent("SharePoint", isDirectory: true), icon: "sharepoint-folder.icns"),
]
let dryRun = CommandLine.arguments.dropFirst().contains("--dry-run")

for mapping in mappings {
    let iconURL = base.appendingPathComponent(mapping.icon)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: mapping.folder.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        fputs("Skipping missing folder: \(mapping.folder.path)\n", stderr)
        continue
    }
    guard let icon = NSImage(contentsOf: iconURL) else {
        fputs("Cannot read icon: \(iconURL.path)\n", stderr)
        exit(1)
    }
    if dryRun {
        print("Would set \(mapping.folder.path) from \(iconURL.lastPathComponent)")
    } else if NSWorkspace.shared.setIcon(icon, forFile: mapping.folder.path, options: []) {
        print("Set folder icon: \(mapping.folder.path)")
    } else {
        fputs("Finder rejected icon for: \(mapping.folder.path)\n", stderr)
        exit(1)
    }
}

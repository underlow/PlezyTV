#!/usr/bin/env swift
// Run from the repository root: swift scripts/plezytv/make_placeholder_icons.swift
// Uses upstream originals from git, so repeated runs never stack badges.
import AppKit
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = "android/app/src/main/res"
let paths = try FileManager.default.subpathsOfDirectory(atPath: resources).filter {
    $0.hasSuffix("/ic_launcher.png") || $0.hasSuffix("/tv_banner.png")
}.sorted()
for path in paths {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    task.arguments = ["show", "598975fb3:\(resources)/\(path)"]
    let pipe = Pipe(); task.standardOutput = pipe
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
    guard task.terminationStatus == 0, let source = NSImage(data: data),
          let original = NSBitmapImageRep(data: data) else { fatalError(path) }
    let width = original.pixelsWide, height = original.pixelsHigh
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    source.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    let h = CGFloat(height) * 0.34, w = h * 1.65
    let rect = NSRect(x: CGFloat(width) - w - CGFloat(width)*0.06, y: CGFloat(height)*0.08, width: w, height: h)
    NSColor(red: 229/255, green: 160/255, blue: 13/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: h*0.15, yRadius: h*0.15).fill()
    let text = NSAttributedString(string: "TV", attributes: [.font: NSFont.boldSystemFont(ofSize: h*0.74), .foregroundColor: NSColor.black])
    let size = text.size()
    text.draw(at: NSPoint(x: rect.midX-size.width/2, y: rect.midY-size.height/2))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("\(resources)/\(path)"))
}
// The adaptive foreground is vector artwork; add the same badge within its safe zone.
let foreground = "\(resources)/drawable/ic_launcher_foreground.xml"
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
process.arguments = ["show", "598975fb3:\(foreground)"]
let output = Pipe(); process.standardOutput = output; try process.run()
let original = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
process.waitUntilExit()
let badge = """
    <group android:scaleX="8.441" android:scaleY="8.441">
    <path android:fillColor="#E5A00D" android:pathData="M48,61 L82,61 L82,79 L48,79 Z"/>
    <path android:fillColor="#16130A" android:pathData="M51,64 L63,64 L63,67 L59,67 L59,76 L55,76 L55,67 L51,67 Z M64,64 L68,64 L72,72 L76,64 L80,64 L74,76 L70,76 Z"/>
    </group>
"""
try original.replacingOccurrences(of: "</vector>", with: badge + "\n</vector>").write(toFile: foreground, atomically: true, encoding: .utf8)

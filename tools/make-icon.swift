// Renders Resources/AppIcon.icns. Run: swift tools/make-icon.swift
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        ZStack {
            // macOS icon grid: 824pt squircle centered in 1024
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.48), Color(red: 0.05, green: 0.06, blue: 0.16)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    RadialGradient(colors: [Color(red: 0.25, green: 0.75, blue: 1).opacity(0.55), .clear],
                                   center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 186, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
                }
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)

            // glass disc
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3))
                .frame(width: 540, height: 540)
                .offset(y: 10)

            // glowing house
            Image(systemName: "house.fill")
                .font(.system(size: 270, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.7, green: 0.9, blue: 1)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(red: 0.3, green: 0.8, blue: 1).opacity(0.9), radius: 40)
                .offset(y: 4)

            // status dot
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.45, green: 1, blue: 0.6), Color(red: 0.1, green: 0.75, blue: 0.35)], startPoint: .top, endPoint: .bottom))
                .frame(width: 92, height: 92)
                .overlay(Circle().strokeBorder(Color(red: 0.08, green: 0.1, blue: 0.25), lineWidth: 12))
                .shadow(color: .green.opacity(0.8), radius: 22)
                .offset(x: 178, y: -168)
        }
        .frame(width: 1024, height: 1024)
    }
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let r = ImageRenderer(content: Icon().scaleEffect(CGFloat(size * scale) / 1024).frame(width: CGFloat(size * scale), height: CGFloat(size * scale)))
            r.scale = 1
            let rep = NSBitmapImageRep(cgImage: r.cgImage!)
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appending(path: name))
        }
    }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try p.run()
p.waitUntilExit()
try FileManager.default.copyItem(at: iconset.appending(path: "icon_512x512@2x.png"), to: root.appending(path: "Resources/AppIcon-preview.png"))
print("ok")

#!/usr/bin/env swift

import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: make-icns.swift ICONSET OUTPUT\n".utf8))
    exit(2)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(type: String, filename: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func bigEndianBytes(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
}

var chunks = Data()
for entry in entries {
    let image = try Data(contentsOf: iconset.appendingPathComponent(entry.filename))
    chunks.append(Data(entry.type.utf8))
    chunks.append(bigEndianBytes(UInt32(image.count + 8)))
    chunks.append(image)
}

var result = Data("icns".utf8)
result.append(bigEndianBytes(UInt32(chunks.count + 8)))
result.append(chunks)
try result.write(to: output, options: .atomic)

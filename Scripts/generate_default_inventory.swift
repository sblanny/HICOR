#!/usr/bin/env swift
import Foundation

struct LensOption: Codable {
    let id: UUID
    let sph: Double
    let cyl: Double
    let available: Bool
}

struct LensInventory: Codable {
    let version: String
    let lastUpdated: Date
    let supportedCylinders: [Double]
    let lenses: [LensOption]
}

let supportedCylinders: [Double] = [0.0, -0.50, -1.00, -1.50, -2.00]

var lenses: [LensOption] = []
var sph = -6.00
let stop = 6.00 + 0.001  // tolerance for floating-point loop bound
while sph < stop {
    let roundedSPH = (sph * 100).rounded() / 100
    for cyl in supportedCylinders {
        lenses.append(LensOption(id: UUID(), sph: roundedSPH, cyl: cyl, available: true))
    }
    sph += 0.25
}

precondition(lenses.count == 245, "Expected 245 lenses, got \(lenses.count)")

let inventory = LensInventory(
    version: "1.0",
    lastUpdated: Date(),
    supportedCylinders: supportedCylinders,
    lenses: lenses
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
let data = try encoder.encode(inventory)

let outURL = URL(fileURLWithPath: "HICOR/Resources/DefaultInventory.json")
try data.write(to: outURL)
print("Wrote \(lenses.count) lenses to \(outURL.path)")

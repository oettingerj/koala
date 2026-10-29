import AppKit
import Observation
import WebKit

/// Camera and microphone choices, remembered per site across launches. Settings › Sites lists them.
@MainActor
@Observable
final class SitePermissions {
    static let shared = SitePermissions()

    /// "origin|type" to allowed. `type` is a `WKMediaCaptureType` raw value.
    private(set) var decisions: [String: Bool] {
        didSet { UserDefaults.standard.set(decisions, forKey: Self.defaultsKey) }
    }

    private static let defaultsKey = "MediaPermissions"

    private init() {
        decisions = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Bool] ?? [:]
    }

    static func key(origin: String, type: WKMediaCaptureType) -> String { "\(origin)|\(type.rawValue)" }

    /// The site and what it asked for, for display.
    static func describe(_ key: String) -> (origin: String, device: String) {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        let type = parts.count == 2 ? Int(parts[1]).flatMap(WKMediaCaptureType.init(rawValue:)) : nil
        return (parts.first ?? key, type.map(deviceName) ?? "Media devices")
    }

    static func deviceName(_ type: WKMediaCaptureType) -> String {
        switch type {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .cameraAndMicrophone: "Camera and microphone"
        @unknown default: "Media devices"
        }
    }

    func decision(origin: String, type: WKMediaCaptureType) -> Bool? { decisions[Self.key(origin: origin, type: type)] }
    func set(_ allowed: Bool, origin: String, type: WKMediaCaptureType) { decisions[Self.key(origin: origin, type: type)] = allowed }
    func set(_ allowed: Bool, key: String) { decisions[key] = allowed }
    func remove(_ key: String) { decisions[key] = nil }
}

/// Page zoom, remembered per site host. Settings › Sites lists it.
@MainActor
@Observable
final class SiteZoom {
    static let shared = SiteZoom()

    private(set) var levels: [String: Double] {
        didSet { UserDefaults.standard.set(levels, forKey: Self.defaultsKey) }
    }

    private static let defaultsKey = "SiteZoom"

    private init() {
        levels = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
    }

    /// 1 (actual size) is not stored.
    subscript(host: String) -> Double {
        get { levels[host] ?? 1 }
        set { levels[host] = newValue == 1 ? nil : newValue }
    }

    func reset(_ host: String) { levels[host] = nil }
}

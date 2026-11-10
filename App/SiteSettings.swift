import AppKit
import BrowserKit
import Observation
import WebKit

/// Camera, microphone, and location choices, remembered per site across launches. Settings › Sites lists them.
@MainActor
@Observable
final class SitePermissions {
    static let shared = SitePermissions()

    /// "origin|kind" to allowed. `kind` is a `WKMediaCaptureType` raw value, or "location".
    private(set) var decisions: [String: Bool] {
        didSet { UserDefaults.standard.set(decisions, forKey: Self.defaultsKey) }
    }

    private static let defaultsKey = "MediaPermissions"
    private static let locationKind = "location"

    private init() {
        decisions = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Bool] ?? [:]
    }

    static func key(origin: String, permission: SitePermission) -> String {
        switch permission {
        case .media(let type): "\(origin)|\(type.rawValue)"
        case .location: "\(origin)|\(locationKind)"
        }
    }

    /// The site and what it asked for, for display.
    static func describe(_ key: String) -> (origin: String, device: String) {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        let kind = parts.count == 2 ? parts[1] : nil
        let permission: SitePermission? = kind == locationKind ? .location
            : kind.flatMap { Int($0) }.flatMap(WKMediaCaptureType.init(rawValue:)).map { .media($0) }
        return (parts.first ?? key, permission.map(deviceName) ?? "Media devices")
    }

    static func deviceName(_ permission: SitePermission) -> String {
        switch permission {
        case .media(.camera): "Camera"
        case .media(.microphone): "Microphone"
        case .media(.cameraAndMicrophone): "Camera and microphone"
        case .media: "Media devices"
        case .location: "Location"
        }
    }

    func decision(origin: String, permission: SitePermission) -> Bool? { decisions[Self.key(origin: origin, permission: permission)] }
    func set(_ allowed: Bool, origin: String, permission: SitePermission) {
        decisions[Self.key(origin: origin, permission: permission)] = allowed
    }
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

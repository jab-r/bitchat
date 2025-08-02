// UWBService.swift
// bitchat
//
// Phase 5: UWB Token Integration Hooks
// - Defines UWBServiceDelegate for token lifecycle callbacks
// - Provides a minimal UWBServiceShim to receive updates from platform UWB provider
// - Wires updates into LoxationProfileManager

import Foundation
import Combine

// Protocol for future UWB service integration
protocol UWBServiceDelegate: AnyObject {
    func uwbTokenDidUpdate(_ token: String)
    func uwbTokenDidExpire()
    func uwbServiceDidBecomeAvailable()
}

/// Minimal shim that a future platform-specific UWB implementation can call into.
/// This service is intentionally simple and only manages token distribution to the profile layer.
final class UWBServiceShim {
    static let shared = UWBServiceShim()

    weak var delegate: UWBServiceDelegate?

    // Publish raw token changes for optional observers (debug/telemetry)
    let tokenPublisher = PassthroughSubject<String?, Never>()

    private let profileManager = LoxationProfileManager()
    private let deviceId = DeviceIDManager.shared.getOrCreateDeviceId()

    private init() {}

    /// Call when a fresh UWB token is available from the system.
    func notifyTokenUpdate(_ token: String) {
        delegate?.uwbTokenDidUpdate(token)
        tokenPublisher.send(token)

        // Update our local profile's uwbToken field. We use our own deviceId as the peerID key.
        profileManager.updateField(for: deviceId, field: .uwbToken, value: token)
    }

    /// Call when the prior token is no longer valid.
    func notifyTokenExpired() {
        delegate?.uwbTokenDidExpire()
        tokenPublisher.send(nil)

        // Clear token in profile
        profileManager.updateField(for: deviceId, field: .uwbToken, value: nil as String?)
    }

    /// Call when the UWB subsystem becomes available (e.g., permissions granted).
    func notifyServiceAvailable() {
        delegate?.uwbServiceDidBecomeAvailable()
    }
}

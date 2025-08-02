// DeviceIDManager.swift
// bitchat
//
// Phase 5: Device ID Management
// - Stable device identifier generation and persistence via Keychain
// - Validation and collision-avoidance hooks
//
// This manager provides a stable deviceId string suitable for use in LoxationProfile.
// It stores the identifier in Keychain to survive app restarts and OS updates.

import Foundation
import CryptoKit

final class DeviceIDManager {
    static let shared = DeviceIDManager()

    private let keychain = KeychainManager.shared
    private let deviceIdKey = "identity_deviceId"

    private init() {}

    /// Returns a stable device identifier string. Generates and persists if missing.
    func getOrCreateDeviceId() -> String {
        if let existing = keychainValue(forKey: deviceIdKey) {
            return existing
        }
        let newId = generateDeviceId()
        _ = saveKeychainValue(newId, forKey: deviceIdKey)
        return newId
    }

    /// Returns the stored device identifier if it exists.
    func getExistingDeviceId() -> String? {
        return keychainValue(forKey: deviceIdKey)
    }

    /// Force set a device identifier (use cautiously). Validates input.
    func setDeviceId(_ id: String) -> Bool {
        let sanitized = sanitizeDeviceId(id)
        guard validateDeviceId(sanitized) else { return false }
        return saveKeychainValue(sanitized, forKey: deviceIdKey)
    }

    /// Generate a new random device ID. 32 hex chars (128-bit) by default.
    func generateDeviceId() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Fallback to CryptoKit random if SecRandom fails
            let rnd = SymmetricKey(size: .bits128)
            return sanitizeDeviceId(rnd.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined())
        }
        return sanitizeDeviceId(bytes.map { String(format: "%02x", $0) }.joined())
    }

    /// Validate an incoming device ID string.
    func validateDeviceId(_ id: String) -> Bool {
        let s = sanitizeDeviceId(id)
        // Allow 8-128 hex chars to be flexible across platforms; prefer 32/64.
        let regex = try! NSRegularExpression(pattern: "^[a-f0-9]{8,128}$")
        let range = NSRange(location: 0, length: s.utf16.count)
        return regex.firstMatch(in: s, options: [], range: range) != nil
    }

    /// Optionally detect collisions given a set of known IDs.
    func wouldCollide(_ id: String, in existing: Set<String>) -> Bool {
        return existing.contains(sanitizeDeviceId(id))
    }

    // MARK: - Private

    private func sanitizeDeviceId(_ id: String) -> String {
        return id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .filter { ("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0)) }
    }

    private func keychainValue(forKey key: String) -> String? {
        // KeychainManager uses generic API only for identity keys; mirror pattern with account key directly.
        // Use the underlying retrieveData via the known naming convention.
        // We cannot access private Keychain methods here; instead, store via identity API with a namespaced key.
        if let data = keychain.getIdentityKey(forKey: key) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func saveKeychainValue(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return keychain.saveIdentityKey(data, forKey: key)
    }
}

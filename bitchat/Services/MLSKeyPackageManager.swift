// MLSKeyPackageManager.swift
// bitchat
//
// Phase 5: MLS Key Package Integration
// - Generates and maintains a local MLS key package via MLSEncryptionService
// - Updates LoxationProfileManager with current keyPackage
// - Provides validation hooks and refresh lifecycle

import Foundation

final class MLSKeyPackageManager {
    static let shared = MLSKeyPackageManager()

    private let mls = MLSEncryptionService.shared
    private let profileManager = LoxationProfileManager()
    private let deviceId = DeviceIDManager.shared.getOrCreateDeviceId()

    // Cache latest key package string (Base64/opaque per SwiftMLS)
    private var currentKeyPackage: String?

    private init() {}

    /// Ensure a key package exists for this device identity and publish into LoxationProfile.
    /// If missing or forceRefresh is true, generates a new key package.
    func ensureKeyPackage(identity: String? = nil, forceRefresh: Bool = false) async {
        let identityStr = identity ?? deviceId

        if !forceRefresh, let existing = currentKeyPackage, !existing.isEmpty {
            // Already have it; ensure profile field is up to date
            profileManager.updateField(for: deviceId, field: .keyPackage, value: existing)
            return
        }

        do {
            let kp = try await mls.generateKeyPackage(identity: identityStr)
            currentKeyPackage = kp
            profileManager.updateField(for: deviceId, field: .keyPackage, value: kp)
        } catch {
            SecureLogger.logError(error, context: "MLSKeyPackageManager.ensureKeyPackage", category: SecureLogger.security)
        }
    }

    /// Explicitly set a validated key package string (e.g., imported or recovered).
    func setKeyPackage(_ kp: String) {
        guard validateKeyPackage(kp) else { return }
        currentKeyPackage = kp
        profileManager.updateField(for: deviceId, field: .keyPackage, value: kp)
    }

    /// Returns latest known key package (may be nil until ensureKeyPackage is called).
    func getCurrentKeyPackage() -> String? {
        return currentKeyPackage
    }

    /// Basic validation placeholder. SwiftMLS treats key packages as opaque strings,
    /// so we perform cheap sanity checks here.
    func validateKeyPackage(_ kp: String) -> Bool {
        // Minimal check: non-empty, reasonable length, base64-like charset
        guard !kp.isEmpty, kp.count < 64_000 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=\n\r")
        return kp.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

// LoxationProfileManager.swift
// bitchat
//
// Phase 1: Core profile support
// - In-memory storage
// - Thread-safe access
// - Update notifications (Combine)
// - Basic validation/sanitization
//
// Later phases will add chunking, transfer state, and Bluetooth integration.

import Foundation
import Combine

final class LoxationProfileManager {
    // MARK: - Storage
    private var profiles: [String: LoxationProfile] = [:] // peerID -> profile
    private let profilesQueue = DispatchQueue(label: "loxation.profiles", attributes: .concurrent)

    // MARK: - Notifications
    let profileUpdates = PassthroughSubject<ProfileUpdate, Never>()

    // MARK: - Public API

    func getProfile(for peerID: String) -> LoxationProfile? {
        var result: LoxationProfile?
        profilesQueue.sync {
            result = profiles[peerID]
        }
        return result
    }

    func getAllProfiles() -> [String: LoxationProfile] {
        var snapshot: [String: LoxationProfile] = [:]
        profilesQueue.sync {
            snapshot = profiles
        }
        return snapshot
    }

    // Set or update profile. Emits ProfileUpdate describing changed fields.
    func setProfile(for peerID: String, profile newProfile: LoxationProfile) {
        guard newProfile.isValid() else { return }
        var old: LoxationProfile?
        profilesQueue.sync {
            old = profiles[peerID]
        }

        let changedFields = diffFields(old: old, new: newProfile)
        profilesQueue.async(flags: .barrier) { [weak self] in
            self?.profiles[peerID] = newProfile
        }

        if !changedFields.isEmpty {
            let update = ProfileUpdate(peerID: peerID,
                                       profile: newProfile,
                                       fields: changedFields,
                                       timestamp: Date())
            profileUpdates.send(update)
        }
    }

    // Update a single field and emit corresponding update
    func updateField(for peerID: String, field: UpdateField, value: Any) {
        profilesQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            let current = self.profiles[peerID]
            var updated = current ?? LoxationProfile(deviceId: peerID) // fallback deviceId as peerID

            switch field {
            case .locationId:
                let v = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                updated = LoxationProfile(deviceId: updated.deviceId,
                                          locationId: v,
                                          uwbToken: updated.uwbToken,
                                          keyPackage: updated.keyPackage,
                                          userProfile: updated.userProfile,
                                          timestamp: Date(),
                                          version: updated.version)
            case .uwbToken:
                let v = value as? String
                updated = LoxationProfile(deviceId: updated.deviceId,
                                          locationId: updated.locationId,
                                          uwbToken: v,
                                          keyPackage: updated.keyPackage,
                                          userProfile: updated.userProfile,
                                          timestamp: Date(),
                                          version: updated.version)
            case .keyPackage:
                let v = value as? String
                updated = LoxationProfile(deviceId: updated.deviceId,
                                          locationId: updated.locationId,
                                          uwbToken: updated.uwbToken,
                                          keyPackage: v,
                                          userProfile: updated.userProfile,
                                          timestamp: Date(),
                                          version: updated.version)
            case .userProfile:
                let v = value as? [String: Any] ?? [:]
                let mapped = v.mapValues { AnyCodable($0) }
                updated = LoxationProfile(deviceId: updated.deviceId,
                                          locationId: updated.locationId,
                                          uwbToken: updated.uwbToken,
                                          keyPackage: updated.keyPackage,
                                          userProfile: mapped,
                                          timestamp: Date(),
                                          version: updated.version)
            }

            self.profiles[peerID] = updated
            let update = ProfileUpdate(peerID: peerID,
                                       profile: updated,
                                       fields: [field],
                                       timestamp: Date())
            self.profileUpdates.send(update)
        }
    }

    // MARK: - Helpers

    private func diffFields(old: LoxationProfile?, new: LoxationProfile) -> Set<UpdateField> {
        var changed: Set<UpdateField> = []

        if old?.locationId != new.locationId {
            changed.insert(.locationId)
        }
        if old?.uwbToken != new.uwbToken {
            changed.insert(.uwbToken)
        }
        if old?.keyPackage != new.keyPackage {
            changed.insert(.keyPackage)
        }
        if old?.userProfile != new.userProfile {
            changed.insert(.userProfile)
        }
        return changed
    }
}

import Foundation
import SwiftMLS

/// MLSEncryptionService: Provides end-to-end encryption using Messaging Layer Security.
class MLSEncryptionService {
    /// Shared singleton instance.
    static let shared = MLSEncryptionService()

    private var mlsClient: MLSClient?

    private init() {}

    /// Initialize the MLS client with a storage path.
    func initialize(storagePath: String? = nil) async throws {
        do {
            mlsClient = try MLSClient(storagePath: storagePath)
        } catch {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize MLS client: \(error.localizedDescription)"])
        }
    }
    
    /// Initialize with an existing MLS client.
    func initialize(mlsClient: MLSClient) async {
        self.mlsClient = mlsClient
    }

    /// Set the storage encryption key for a user.
    func setStorageKey(userId: String, key: String) async throws {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        client.setStorageKey(userId: userId, key: key)
    }

    /// Rekey the storage encryption key for a user.
    func setStorageRekey(userId: String, oldKey: String, newKey: String) async throws {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        client.setStorageRekey(userId: userId, oldKey: oldKey, newKey: newKey)
    }

    /// Create a new MLS group.
    func createGroup(groupId: String, creatorId: String) async throws {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        _ = try client.createGroup(groupId: groupId, creatorId: creatorId)
    }

    /// Join an existing MLS group.
    func joinGroup(groupId: String, receiverId: String, welcomeMessage: String) async throws {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        _ = try client.joinGroup(groupId: groupId, receiverId: receiverId, welcomeMessage: welcomeMessage)
    }

    /// Join an existing MLS group with a ratchet tree.
    func joinGroupWithRatchetTree(groupId: String, receiverId: String, welcomeMessage: String, ratchetTree: String) async throws {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        _ = try client.joinGroup(groupId: groupId, receiverId: receiverId, welcomeMessage: welcomeMessage, ratchetTree: ratchetTree)
    }

    /// Export the ratchet tree for a group.
    func exportRatchetTree(groupId: String, userId: String) async throws -> String {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        let data = try client.exportRatchetTree(groupId: groupId, userId: userId)
        return data.base64EncodedString()
    }

    /// Add a member to a MLS group.
    func addMember(groupId: String, creatorId: String, receiverId: String, keyPackage: String) async throws {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        _ = try client.addMember(groupId: groupId, creatorId: creatorId, receiverId: receiverId, keyPackage: keyPackage)
    }

    /// Add multiple members to a MLS group.
    func addMembers(groupId: String, creatorId: String, receiverKeyPackages: [String]) async throws {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        // Note: SwiftMLS doesn't have a direct addMembers method, so we'll add them one by one
        for keyPackage in receiverKeyPackages {
            _ = try client.addMember(groupId: groupId, creatorId: creatorId, receiverId: "", keyPackage: keyPackage)
        }
    }

    /// Remove members from a MLS group.
    func removeMembers(groupId: String, creatorId: String, memberIndices: [Int]) async throws {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        // Note: SwiftMLS doesn't have a direct removeMembers method
        // This would need to be implemented using proposals and commits
        throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "removeMembers not yet implemented in SwiftMLS"])
    }

    /// Commit pending proposals in a MLS group.
    func commitPendingProposals(groupId: String, creatorId: String) async throws {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        _ = try client.commitPendingProposals(groupId: groupId, creatorId: creatorId)
    }

    /// Generate a key package for an identity.
    func generateKeyPackage(identity: String) async throws -> String {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        return try client.generateKeyPackage(identity: identity)
    }

    /// Generate multiple key packages for an identity.
    func generateKeyPackages(identity: String, count: Int) async throws -> [String] {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        // Generate multiple key packages by calling generateKeyPackage multiple times
        var keyPackages: [String] = []
        for _ in 0..<count {
            let keyPackage = try client.generateKeyPackage(identity: identity)
            keyPackages.append(keyPackage)
        }
        return keyPackages
    }

    /// Import a key package for an identity.
    func importKeyPackage(identity: String, keyPackage: String) async throws {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        // Note: SwiftMLS doesn't have a direct importKeyPackage method
        // This would need to be implemented differently
        throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "importKeyPackage not yet implemented in SwiftMLS"])
    }

    /// Export a secret from a MLS group.
    func exportSecret(groupId: String, creatorId: String, label: String, context: String, length: Int) async throws -> String {
        guard let client = mlsClient else {
            throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "MLS client not initialized"])
        }
        // Note: SwiftMLS doesn't have a direct exportSecret method
        // This would need to be implemented differently
        throw NSError(domain: "MLSEncryptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "exportSecret not yet implemented in SwiftMLS"])
    }
}
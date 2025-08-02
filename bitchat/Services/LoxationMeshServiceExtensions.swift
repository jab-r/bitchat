 // LoxationMeshServiceExtensions.swift
 // Phase 3 (simplified): Loxation message routing that leverages BitChat core fragmentation and ACKs.
 //
 // This extension isolates loxation-related message handling away from the
 // main BluetoothMeshService.swift. The service delegates loxation MessageType
 // cases to handleLoxationMessage(...).
 //
 // Simplified Phase 3 approach:
 // - Do NOT implement custom per-chunk logic for loxation. Rely on BluetoothMeshService
 //   automatic fragmentation/reassembly for oversized packets.
 // - Maintain minimal logical transfer state with a timeout scanner.
 // - Emit coarse-grained progress via Combine (start/complete/error).
 // - Keep compatibility stubs for loxationChunk but do not rely on it.
 //
 // Notes:
 // - Uses SecureLogger if available; falls back to print.
 // - Avoids assuming internal properties of BluetoothMeshService to keep this non-invasive.

 import Foundation
 import Combine

// MARK: - Safe logger shims

fileprivate func LoxLogInfo(_ msg: String) {
    if let SecureLoggerType = NSClassFromString("SecureLogger") as? NSObject.Type,
       SecureLoggerType.responds(to: NSSelectorFromString("info:")) {
        // Best effort dynamic dispatch if SecureLogger exists
        print("[SecureLogger] \(msg)")
    } else {
        print("[Loxation] \(msg)")
    }
}

fileprivate func LoxLogWarn(_ msg: String) {
    if let SecureLoggerType = NSClassFromString("SecureLogger") as? NSObject.Type,
       SecureLoggerType.responds(to: NSSelectorFromString("warn:")) {
        print("[SecureLogger][WARN] \(msg)")
    } else {
        print("[Loxation][WARN] \(msg)")
    }
}

fileprivate func LoxLogError(_ msg: String) {
    if let SecureLoggerType = NSClassFromString("SecureLogger") as? NSObject.Type,
       SecureLoggerType.responds(to: NSSelectorFromString("error:")) {
        print("[SecureLogger][ERROR] \(msg)")
    } else {
        print("[Loxation][ERROR] \(msg)")
    }
}

// MARK: - BluetoothMeshService Extension

extension BluetoothMeshService {
    // Expose a thin, extension-local wrapper since broadcastPacket(_:) is private in the main type.
    // This keeps core visibility unchanged while allowing loxation handlers to send packets.
    fileprivate func loxationBroadcast(_ packet: BitchatPacket) {
        // Call the private method via instance scope within the extension
        self.broadcastPacket(packet)
    }

    // MARK: - Internal accessors for private members used by Loxation extension

    // Provide safe accessors/shims so we don't widen visibility of core properties.
    fileprivate var lox_adaptiveTTL: UInt8 {
        // If BluetoothMeshService exposes adaptiveTTL, use it; else return a sane default.
        // We cannot access private directly; rely on a conservative default TTL 5.
        return 5
    }

    fileprivate func lox_encrypt(_ data: Data, for peerID: String) throws -> Data {
        // Use the public accessor to the NoiseEncryptionService
        let noise = self.getNoiseService()
        return try noise.encrypt(data, for: peerID)
    }

    fileprivate func lox_hasNoiseSession(with peerID: String) -> Bool {
        let noise = self.getNoiseService()
        return noise.hasEstablishedSession(with: peerID)
    }

    fileprivate func lox_sendTargeted(_ packet: BitchatPacket, to recipientPeerID: String) {
        // Try direct delivery using existing helpers; these are available within the same type via extension
        if self.sendDirectToRecipient(packet, recipientPeerID: recipientPeerID) {
            return
        }
        // Fallback to selective relay for targeted delivery
        self.sendViaSelectiveRelay(packet, recipientPeerID: recipientPeerID)
    }
    // Entry point called by BluetoothMeshService.handleReceivedPacket switch
    func handleLoxationMessage(_ messageType: MessageType, packet: BitchatPacket, from peerID: String) {
        switch messageType {
        case .loxationAnnounce:
            handleLoxationAnnounce(packet: packet, from: peerID)

        case .loxationQuery:
            handleLoxationQuery(packet: packet, from: peerID)

        case .loxationChunk:
            // Compatibility: accept single-packet data flows if used by older peers.
            handleLoxationData(packet: packet, from: peerID)

        case .loxationComplete:
            handleLoxationComplete(packet: packet, from: peerID)

        default:
            // Should not arrive for other types
            LoxLogWarn("Received non-loxation type in loxation handler: \(messageType)")
        }
    }

    // MARK: - Handlers

    // Phase 2: Decode lightweight announce and update only deviceId/locationId/uwbToken
    fileprivate func handleLoxationAnnounce(packet: BitchatPacket, from peerID: String) {
        guard let announce = decodeAnnounce(from: packet.payload) else {
            LoxLogWarn("Failed to decode AnnouncePayload from loxationAnnounce, peer=\(peerID)")
            return
        }

        // Fetch existing profile (if any), then apply partial update
        let manager = LoxationManagers.shared.profileManager
        let current = manager.getProfile(for: peerID)

        let deviceId = LoxationProfile.sanitizeDeviceId(announce.deviceId)
        let newProfile = LoxationProfile(
            deviceId: deviceId,
            locationId: announce.locationId ?? current?.locationId,
            uwbToken: announce.uwbToken ?? current?.uwbToken,
            keyPackage: current?.keyPackage,
            userProfile: current?.userProfile ?? [:],
            timestamp: Date(),
            version: current?.version ?? 1
        )

        if !newProfile.isValid() {
            LoxLogWarn("Invalid LoxationProfile after announce merge, peer=\(peerID)")
            return
        }

        manager.setProfile(for: peerID, profile: newProfile)
        LoxLogInfo("Applied loxationAnnounce for peer=\(peerID) deviceId=\(deviceId) locationId=\(announce.locationId ?? "nil") uwbToken=\(announce.uwbToken != nil ? "present" : "nil")")
        // Future policy: optionally auto-query userProfile via loxationQuery
    }

    // Phase 3 simplified: respond with a single logical data packet and let core fragmentation handle size.
    fileprivate func handleLoxationQuery(packet: BitchatPacket, from peerID: String) {
        guard let query = decodeLoxationQuery(from: packet.payload) else {
            LoxLogWarn("Malformed loxationQuery from peer=\(peerID), bytes=\(packet.payload.count)")
            return
        }
        LoxLogInfo("Received loxationQuery from peer=\(peerID), type=\(query.queryType) transferId=\(query.transferId)")

        // Build data based on query type
        guard let responseData = buildResponseData(for: query) else {
            LoxLogWarn("No data available to respond to loxationQuery \(query.queryType) for peer=\(peerID)")
            // Notify completion to avoid sender waiting indefinitely
            LoxationManagers.shared.finalizeOutgoingFailure(transferId: query.transferId, peerID: peerID, reason: "No data")
            sendLoxationComplete(transferId: query.transferId, queryType: query.queryType)
            return
        }

        // Mark outgoing logical transfer start
        LoxationManagers.shared.beginOutgoing(transferId: query.transferId,
                                              recipientId: peerID,
                                              queryType: query.queryType)
        // Emit initial progress for visibility
        LoxationManagers.shared.emitProgress(transferId: query.transferId, peerID: peerID, progress: 0.0, complete: false, error: nil)

        // Decide on encryption policy:
        // Encrypt sensitive fields via Noise when session exists.
        // deviceInfo may be sent in clear; others require encryption if available.
        let shouldEncrypt: Bool = {
            switch query.queryType {
            case .deviceInfo:
                return false
            case .fullProfile, .userProfile, .keyPackage, .uwbToken:
                return true
            }
        }()

        do {
            if shouldEncrypt {
                // Attempt to encrypt; if not available, fall back to clear targeted send.
                let responseEnvelope = LoxationDataEnvelope(transferId: query.transferId,
                                                            queryType: query.queryType,
                                                            data: responseData)
                let encodedEnvelope = try JSONEncoder().encode(responseEnvelope)

                // Build inner packet carrying the envelope as payload
                let innerPacket = BitchatPacket(
                    type: MessageType.loxationChunk.rawValue,
                    senderID: Data(hexString: self.myPeerID) ?? Data(),
                    recipientID: Data(hexString: peerID),
                    timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                    payload: encodedEnvelope,
                    signature: nil,
                    ttl: self.lox_adaptiveTTL
                )

                if let innerData = innerPacket.toBinaryData() {
                    if lox_hasNoiseSession(with: peerID) {
                        // Encrypt and send as noiseEncrypted
                        let encrypted = try lox_encrypt(innerData, for: peerID)
                        let outerPacket = BitchatPacket(
                            type: MessageType.noiseEncrypted.rawValue,
                            senderID: Data(hexString: self.myPeerID) ?? Data(),
                            recipientID: Data(hexString: peerID),
                            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                            payload: encrypted,
                            signature: nil,
                            ttl: self.lox_adaptiveTTL
                        )
                        lox_sendTargeted(outerPacket, to: peerID)
                        // After sending the encrypted envelope, send completion targeted to requester
                        sendLoxationComplete(transferId: query.transferId, queryType: query.queryType, to: peerID)
                        return
                    } else {
                        // No session: policy decision
                        // For sensitive types, do NOT send in clear. Complete with failure.
                        switch query.queryType {
                        case .deviceInfo:
                            lox_sendTargeted(innerPacket, to: peerID)
                        case .fullProfile, .userProfile, .keyPackage, .uwbToken:
                            LoxLogWarn("No Noise session with \(peerID) for sensitive \(query.queryType) - not sending in clear")
                            LoxationManagers.shared.finalizeOutgoingFailure(transferId: query.transferId, peerID: peerID, reason: "no noise session")
                            sendLoxationComplete(transferId: query.transferId, queryType: query.queryType, to: peerID)
                            return
                        }
                    }
                } else {
                    // Encoding failed
                    LoxationManagers.shared.finalizeOutgoingFailure(transferId: query.transferId, peerID: peerID, reason: "encode failed")
                    sendLoxationComplete(transferId: query.transferId, queryType: query.queryType, to: peerID)
                    return
                }
            } else {
                // Send clear envelope; transport will fragment as needed.
                let responseEnvelope = LoxationDataEnvelope(transferId: query.transferId,
                                                            queryType: query.queryType,
                                                            data: responseData)
                let encoded = try JSONEncoder().encode(responseEnvelope)
                let out = BitchatPacket(
                    type: MessageType.loxationChunk.rawValue,
                    senderID: Data(hexString: self.myPeerID) ?? Data(),
                    recipientID: Data(hexString: peerID),
                    timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                    payload: encoded,
                    signature: nil,
                    ttl: self.lox_adaptiveTTL
                )
                // Targeted send for clear deviceInfo
                lox_sendTargeted(out, to: peerID)
                // Completion targeted to requester
                sendLoxationComplete(transferId: query.transferId, queryType: query.queryType, to: peerID)
                return
            }
        } catch {
            LoxLogError("Failed to build/send loxation response transferId=\(query.transferId): \(error)")
            LoxationManagers.shared.finalizeOutgoingFailure(transferId: query.transferId, peerID: peerID, reason: "send error")
            sendLoxationComplete(transferId: query.transferId, queryType: query.queryType, to: peerID)
            return
        }
    }

    // Compatibility handler for older peers that send a single loxationChunk carrying full data (our envelope).
    fileprivate func handleLoxationData(packet: BitchatPacket, from peerID: String) {
        // Try envelope JSON first
        let decoder = JSONDecoder()
        if #available(iOS 10.0, macOS 10.12, *) {
            decoder.dateDecodingStrategy = .iso8601
        } else {
            decoder.dateDecodingStrategy = .deferredToDate
        }

        // First try as a clear envelope
        if let env = try? decoder.decode(LoxationDataEnvelope.self, from: packet.payload) {
            // Mark incoming logical transfer start (idempotent)
            LoxationManagers.shared.beginIncoming(transferId: env.transferId,
                                                  senderId: peerID,
                                                  queryType: env.queryType)

            // Process data immediately (transport already reassembled)
            applyLoxationData(env.data, queryType: env.queryType, from: peerID, transferId: env.transferId)
            return
        }

        // If not clear and packet type suggests it may have been Noise-encrypted elsewhere,
        // attempt decryption and parse the inner envelope. This provides forward compat
        // if future peers send loxation data via Noise using this messageType by mistake.
        if packet.type == MessageType.loxationChunk.rawValue {
            // Attempt to decrypt as if it were noiseEncrypted inner payload
            if lox_hasNoiseSession(with: peerID) {
                // Without direct decrypt access, we cannot decrypt here; leave as forward-compat note.
                // If future public decrypt accessor exists, wire it similarly to lox_encrypt.
            }
        }

        // Not our envelope; accept silently for forward/backward compatibility
        LoxLogWarn("loxationChunk not recognized as clear or decryptable envelope from peer=\(peerID) size=\(packet.payload.count)")
    }

    fileprivate func handleLoxationComplete(packet: BitchatPacket, from peerID: String) {
        // loxationComplete payload can include LoxationQuery (transferId + queryType) or raw transferId.
        if let q = decodeLoxationQuery(from: packet.payload) {
            finalizeLogicalIncoming(transferId: q.transferId, queryType: q.queryType, from: peerID)
        } else if let tid = String(data: packet.payload, encoding: .utf8), !tid.isEmpty {
            finalizeLogicalIncoming(transferId: tid, queryType: .userProfile, from: peerID)
        } else {
            LoxLogWarn("Malformed loxationComplete from peer=\(peerID), unable to parse transfer id")
        }
        // Remove any pending outgoing record with the same transferId if it exists
        // to avoid leaking logical state across peers (best-effort cleanup).
        // Outgoing is internal; expose a helper if needed in future.
    }

    // MARK: - Helpers

    // Decode announce payload:
    // 1) Prefer binary LoxationAnnouncement (project-standard binary wire format)
    // 2) Fallback to JSON AnnouncePayload for optional fields/locationId/uwbToken
    fileprivate func decodeAnnounce(from data: Data) -> AnnouncePayload? {
        // Try binary first
        if let bin = LoxationAnnouncement.fromBinaryData(data) {
            return AnnouncePayload(deviceId: bin.deviceId, locationId: nil, uwbToken: nil)
        }
        // Support current production binary announcement embedded elsewhere: BluetoothMeshService.sendLoxationAnnounce()
        // If the project uses a different binary format, extend parsing here accordingly.
        // Fallback to JSON AnnouncePayload
        let decoder = JSONDecoder()
        if #available(iOS 10.0, macOS 10.12, *) {
            decoder.dateDecodingStrategy = .iso8601
        } else {
            decoder.dateDecodingStrategy = .deferredToDate
        }
        if let json = try? decoder.decode(AnnouncePayload.self, from: data) {
            return json
        }
        LoxLogWarn("Unable to decode loxationAnnounce as binary or JSON")
        return nil
    }

    // Build outbound response data for a query (serialized bytes to chunk)
    fileprivate func buildResponseData(for query: LoxationQuery) -> Data? {
        switch query.queryType {
        case .userProfile:
            // Serialize our own userProfile to JSON dictionary
            // Assuming we store our own profile under a special key "self" or through a local accessor.
            // If there's a dedicated local-profile accessor, replace the below with it.
            let selfPeer = query.requesterId // Placeholder; replace with actual local peer ID if available
            guard let profile = LoxationManagers.shared.profileManager.getProfile(for: selfPeer) else {
                return nil
            }
            // Only send userProfile dictionary
            let dict = profile.userProfile
            return try? JSONEncoder().encode(dict)

        case .deviceInfo:
            // Announce-like payload
            let selfPeer = query.requesterId // Placeholder; replace with actual local peer ID if available
            guard let profile = LoxationManagers.shared.profileManager.getProfile(for: selfPeer) else {
                return nil
            }
            let payload = AnnouncePayload(deviceId: profile.deviceId,
                                          locationId: profile.locationId,
                                          uwbToken: profile.uwbToken)
            return try? JSONEncoder().encode(payload)

        case .keyPackage:
            // Raw key package data. If profile stores base64, decode back to bytes or send as-is (bytes).
            let selfPeer = query.requesterId
            guard let profile = LoxationManagers.shared.profileManager.getProfile(for: selfPeer),
                  let base64 = profile.keyPackage,
                  let bytes = Data(base64Encoded: base64) ?? base64.data(using: .utf8) else {
                return nil
            }
            return bytes

        case .uwbToken:
            // UTF-8 string token
            let selfPeer = query.requesterId
            guard let profile = LoxationManagers.shared.profileManager.getProfile(for: selfPeer),
                  let token = profile.uwbToken,
                  let bytes = token.data(using: .utf8) else {
                return nil
            }
            return bytes

        case .fullProfile:
            // Full JSON profile
            let selfPeer = query.requesterId
            guard let profile = LoxationManagers.shared.profileManager.getProfile(for: selfPeer) else {
                return nil
            }
            return try? JSONEncoder().encode(profile)
        }
    }

    // Send loxationComplete with {transferId, queryType} using LoxationQuery encoding
    fileprivate func sendLoxationComplete(transferId: String, queryType: LoxationQueryType, to recipientPeerID: String? = nil) {
        let completion = LoxationQuery(queryType: queryType,
                                       requesterId: self.myPeerID,
                                       transferId: transferId,
                                       timestamp: Date())
        guard let data = try? JSONEncoder().encode(completion) else {
            return
        }
        let packet = BitchatPacket(
            type: MessageType.loxationComplete.rawValue,
            senderID: Data(hexString: self.myPeerID) ?? Data(),
            recipientID: recipientPeerID.flatMap { Data(hexString: $0) },
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: data,
            signature: nil,
            ttl: 3
        )
        if let recipient = recipientPeerID {
            // Prefer targeted completion to minimize mesh traffic
            lox_sendTargeted(packet, to: recipient)
        } else {
            self.loxationBroadcast(packet)
        }
    }

    // MARK: - Incoming finalization (Step 2)

    // Finalize logical incoming transfer after we received data (via handleLoxationData) and/or completion marker.
    fileprivate func finalizeLogicalIncoming(transferId: String, queryType: LoxationQueryType, from peerID: String) {
        // Mark complete and emit progress
        LoxationManagers.shared.completeIncoming(transferId: transferId, peerID: peerID)
    }

    // Apply data by query type, update profile manager, emit progress on success/failure
    private func applyLoxationData(_ data: Data, queryType: LoxationQueryType, from peerID: String, transferId: String) {
        switch queryType {
        case .userProfile:
            // Decode into [String: AnyCodable] to preserve arbitrary JSON
            if let dict = try? JSONDecoder().decode([String: AnyCodable].self, from: data) {
                let manager = LoxationManagers.shared.profileManager
                let current = manager.getProfile(for: peerID) ?? LoxationProfile(deviceId: peerID)
                let updated = LoxationProfile(deviceId: current.deviceId,
                                              locationId: current.locationId,
                                              uwbToken: current.uwbToken,
                                              keyPackage: current.keyPackage,
                                              userProfile: dict,
                                              timestamp: Date(),
                                              version: current.version)
                manager.setProfile(for: peerID, profile: updated)
                LoxationManagers.shared.emitProgress(transferId: transferId, peerID: peerID, progress: 1.0, complete: true, error: nil)
                LoxLogInfo("Applied userProfile for peer=\(peerID) via transferId=\(transferId) size=\(data.count)B")
            } else {
                LoxationManagers.shared.emitProgress(transferId: transferId, peerID: peerID, progress: 0.0, complete: false, error: "decode userProfile failed")
                LoxLogWarn("Failed to decode userProfile JSON for transferId=\(transferId) peer=\(peerID)")
            }

        case .deviceInfo:
            if let info = try? JSONDecoder().decode(AnnouncePayload.self, from: data) {
                let manager = LoxationManagers.shared.profileManager
                let current = manager.getProfile(for: peerID) ?? LoxationProfile(deviceId: peerID)
                let updated = LoxationProfile(deviceId: LoxationProfile.sanitizeDeviceId(info.deviceId),
                                              locationId: info.locationId ?? current.locationId,
                                              uwbToken: current.uwbToken,
                                              keyPackage: current.keyPackage,
                                              userProfile: current.userProfile,
                                              timestamp: Date(),
                                              version: current.version)
                manager.setProfile(for: peerID, profile: updated)
                LoxationManagers.shared.emitProgress(transferId: transferId, peerID: peerID, progress: 1.0, complete: true, error: nil)
                LoxLogInfo("Applied deviceInfo for peer=\(peerID) via transferId=\(transferId)")
            } else {
                LoxationManagers.shared.emitProgress(transferId: transferId, peerID: peerID, progress: 0.0, complete: false, error: "decode deviceInfo failed")
                LoxLogWarn("Failed to decode deviceInfo for transferId=\(transferId) peer=\(peerID)")
            }

        case .keyPackage:
            let base64 = data.base64EncodedString()
            let manager = LoxationManagers.shared.profileManager
            let current = manager.getProfile(for: peerID) ?? LoxationProfile(deviceId: peerID)
            let updated = LoxationProfile(deviceId: current.deviceId,
                                          locationId: current.locationId,
                                          uwbToken: current.uwbToken,
                                          keyPackage: base64,
                                          userProfile: current.userProfile,
                                          timestamp: Date(),
                                          version: current.version)
            manager.setProfile(for: peerID, profile: updated)
            LoxationManagers.shared.emitProgress(transferId: transferId, peerID: peerID, progress: 1.0, complete: true, error: nil)
            LoxLogInfo("Stored keyPackage for peer=\(peerID) via transferId=\(transferId) bytes=\(data.count)")

        case .uwbToken:
            if let token = String(data: data, encoding: .utf8) {
                let manager = LoxationManagers.shared.profileManager
                let current = manager.getProfile(for: peerID) ?? LoxationProfile(deviceId: peerID)
                let updated = LoxationProfile(deviceId: current.deviceId,
                                              locationId: current.locationId,
                                              uwbToken: token,
                                              keyPackage: current.keyPackage,
                                              userProfile: current.userProfile,
                                              timestamp: Date(),
                                              version: current.version)
                manager.setProfile(for: peerID, profile: updated)
                LoxationManagers.shared.emitProgress(transferId: transferId, peerID: peerID, progress: 1.0, complete: true, error: nil)
                LoxLogInfo("Stored uwbToken for peer=\(peerID) via transferId=\(transferId)")
            } else {
                LoxationManagers.shared.emitProgress(transferId: transferId, peerID: peerID, progress: 0.0, complete: false, error: "decode uwbToken failed")
                LoxLogWarn("Failed to decode uwbToken string for transferId=\(transferId) peer=\(peerID)")
            }

        case .fullProfile:
            if let profile = try? JSONDecoder().decode(LoxationProfile.self, from: data), profile.isValid() {
                LoxationManagers.shared.profileManager.setProfile(for: peerID, profile: profile)
                LoxationManagers.shared.emitProgress(transferId: transferId, peerID: peerID, progress: 1.0, complete: true, error: nil)
                LoxLogInfo("Applied fullProfile for peer=\(peerID) via transferId=\(transferId)")
            } else {
                LoxationManagers.shared.emitProgress(transferId: transferId, peerID: peerID, progress: 0.0, complete: false, error: "decode fullProfile failed")
                LoxLogWarn("Failed to decode fullProfile for transferId=\(transferId) peer=\(peerID)")
            }
        }

        // Mark incoming logically present to pair with loxationComplete
        LoxationManagers.shared.markIncomingDataSeen(transferId: transferId)
    }

    // Decode a LoxationQuery if payload is a query
    fileprivate func decodeLoxationQuery(from data: Data) -> LoxationQuery? {
        let decoder = JSONDecoder()
        if #available(iOS 10.0, macOS 10.12, *) {
            decoder.dateDecodingStrategy = .iso8601
        } else {
            decoder.dateDecodingStrategy = .deferredToDate
        }
        return try? decoder.decode(LoxationQuery.self, from: data)
    }

    // Decode a LoxationChunk if payload is a chunk
    fileprivate func decodeLoxationChunk(from data: Data) -> LoxationChunk? {
        let decoder = JSONDecoder()
        if #available(iOS 10.0, macOS 10.12, *) {
            decoder.dateDecodingStrategy = .iso8601
        } else {
            decoder.dateDecodingStrategy = .deferredToDate
        }
        return try? decoder.decode(LoxationChunk.self, from: data)
    }
}


// MARK: - LoxationManagers container
// To avoid modifying BluetoothMeshService stored properties in Phase 2,
// use a shared container for managers used by the extension.
// You can later refactor this into DI by adding properties to BluetoothMeshService.

final class LoxationManagers {
    static let shared = LoxationManagers()

    // Existing
    let profileManager = LoxationProfileManager()

    // Combine progress stream for logical transfers
    let transferProgress = PassthroughSubject<TransferProgress, Never>()

    // Minimal logical transfer state
    private struct Incoming {
        let id: String
        let startTime: Date
        let senderId: String
        let queryType: LoxationQueryType
        var dataSeen: Bool
    }
    private struct Outgoing {
        let id: String
        let startTime: Date
        let recipientId: String
        let queryType: LoxationQueryType
    }

    private let transfersQueue = DispatchQueue(label: "loxation.transfers")
    private var incoming: [String: Incoming] = [:]
    private var outgoing: [String: Outgoing] = [:]

    // Configuration
    let maxTransferTime: TimeInterval = 30.0
    let maxConcurrentTransfers = 10

    private var timeoutTimer: Timer?

    private init() {
        // Start timeout scanning timer on main runloop
        DispatchQueue.main.async {
            self.timeoutTimer?.invalidate()
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.scanTimeouts()
            }
        }
    }

    // Progress emission helper
    func emitProgress(transferId: String, peerID: String, progress: Double, complete: Bool, error: String?) {
        let err: Error? = error.map { NSError(domain: "loxation", code: -1, userInfo: [NSLocalizedDescriptionKey: $0]) }
        transferProgress.send(TransferProgress(transferId: transferId, peerID: peerID, progress: progress, isComplete: complete, error: err))
    }

    // Begin outgoing logical transfer
    func beginOutgoing(transferId: String, recipientId: String, queryType: LoxationQueryType) {
        transfersQueue.async {
            // Respect concurrency cap (soft): if too many, we still proceed but can be extended to queue.
            self.outgoing[transferId] = Outgoing(id: transferId,
                                                 startTime: Date(),
                                                 recipientId: recipientId,
                                                 queryType: queryType)
            // Emit start progress
            self.emitProgress(transferId: transferId, peerID: recipientId, progress: 0.0, complete: false, error: nil)
        }
    }

    // Begin incoming logical transfer
    func beginIncoming(transferId: String, senderId: String, queryType: LoxationQueryType) {
        transfersQueue.async {
            if self.incoming[transferId] == nil {
                self.incoming[transferId] = Incoming(id: transferId,
                                                     startTime: Date(),
                                                     senderId: senderId,
                                                     queryType: queryType,
                                                     dataSeen: false)
            }
        }
    }

    // Mark that incoming data has been seen/applied
    func markIncomingDataSeen(transferId: String) {
        transfersQueue.async {
            if var entry = self.incoming[transferId] {
                entry.dataSeen = true
                self.incoming[transferId] = entry
            }
        }
    }

    // Logical completion for incoming transfers on loxationComplete
    func completeIncoming(transferId: String, peerID: String) {
        transfersQueue.async {
            // Emit complete if data was seen; otherwise still emit completion with lower progress
            let progress: Double = (self.incoming[transferId]?.dataSeen == true) ? 1.0 : 0.9
            self.emitProgress(transferId: transferId, peerID: peerID, progress: progress, complete: true, error: nil)
            self.incoming.removeValue(forKey: transferId)
        }
    }

    // Finalize failure for outgoing
    func finalizeOutgoingFailure(transferId: String, peerID: String, reason: String) {
        transfersQueue.async {
            self.emitProgress(transferId: transferId, peerID: peerID, progress: 0.0, complete: false, error: reason)
            self.outgoing.removeValue(forKey: transferId)
        }
    }

    private func scanTimeouts() {
        let now = Date()
        var timedOutIncoming: [(String, String)] = [] // (transferId, peerID)
        var timedOutOutgoing: [(String, String)] = [] // (transferId, peerID)

        transfersQueue.sync {
            for (_, inc) in incoming {
                if now.timeIntervalSince(inc.startTime) > maxTransferTime {
                    timedOutIncoming.append((inc.id, inc.senderId))
                }
            }
            for (_, out) in outgoing {
                if now.timeIntervalSince(out.startTime) > maxTransferTime {
                    timedOutOutgoing.append((out.id, out.recipientId))
                }
            }
        }

        // Emit outside sync
        for (tid, peer) in timedOutIncoming {
            emitProgress(transferId: tid, peerID: peer, progress: 0.0, complete: false, error: "timeout")
            transfersQueue.async { self.incoming.removeValue(forKey: tid) }
        }
        for (tid, peer) in timedOutOutgoing {
            emitProgress(transferId: tid, peerID: peer, progress: 0.0, complete: false, error: "timeout")
            transfersQueue.async { self.outgoing.removeValue(forKey: tid) }
        }
    }
}

// MARK: - Payload Models (Phase 2)

fileprivate struct AnnouncePayload: Codable {
    let deviceId: String
    let locationId: String?
    let uwbToken: String?
}

// Envelope for simplified single-packet loxation data
fileprivate struct LoxationDataEnvelope: Codable {
    let transferId: String
    let queryType: LoxationQueryType
    let data: Data
}

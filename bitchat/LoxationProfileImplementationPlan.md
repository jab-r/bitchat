# Loxation Profile Implementation Plan

## Overview

This document outlines the implementation of Loxation-specific fields in the BitChat Bluetooth mesh network, including device identification, UWB tokens, MLS key packages, and arbitrary user profiles.

## 1. Core Data Structures

### LoxationProfile
```swift
struct LoxationProfile: Codable {
    // Core Identity
    let deviceId: String        // Stable device identifier
    let locationId: String?     // Optional location identifier
    
    // Tokens & Keys
    let uwbToken: String?       // UWB token from iOS UWBService
    let keyPackage: String?     // Base64 encoded MLS key package
    
    // User Data
    let userProfile: [String: Any]  // Arbitrary JSON profile data
    
    // Metadata
    let timestamp: Date         // Last update timestamp
    let version: UInt8 = 1      // Protocol version
    
    // Computed properties
    var serializedSize: Int {
        (try? JSONEncoder().encode(self))?.count ?? 0
    }
    
    var needsChunking: Bool {
        serializedSize > 450  // Account for packet overhead
    }
}
```

### Supporting Structures
```swift
struct LoxationChunk: Codable {
    let transferId: String      // UUID for this transfer session
    let chunkIndex: UInt16      // Current chunk number (0-based)
    let totalChunks: UInt16     // Total expected chunks
    let data: Data             // Chunk payload
    let checksum: UInt32       // CRC32 checksum for integrity
}

struct LoxationQuery: Codable {
    let queryType: LoxationQueryType
    let requesterId: String
    let transferId: String      // For tracking responses
    let timestamp: Date
}

struct LoxationUpdate: Codable {
    let field: UpdateField
    let value: Data            // Serialized field value
    let timestamp: Date
    let signature: Data?       // Optional signature for verification
}

enum LoxationQueryType: UInt8, Codable {
    case fullProfile = 0x01    // Complete profile
    case deviceInfo = 0x02     // deviceId + locationId only
    case keyPackage = 0x03     // MLS key package only
    case userProfile = 0x04    // Custom JSON data only
    case uwbToken = 0x05       // UWB token only
}

enum UpdateField: String, Codable, CaseIterable {
    case locationId
    case uwbToken
    case keyPackage
    case userProfile
}
```

## 2. Message Protocol

### New Message Types
Add to existing `MessageType` enum:
```swift
enum MessageType: UInt8 {
    // ... existing types ...
    case loxationAnnounce = 0x40      // Profile announcement
    case loxationQuery = 0x41         // Request profile data
    case loxationChunk = 0x42         // Profile chunk data
    case loxationComplete = 0x43      // Transfer completion
    case loxationUpdate = 0x44        // Field update notification
}
```

### Message Format
All Loxation messages follow the standard BitchatPacket format:
- Standard packet header
- Loxation-specific payload
- Optional encryption via Noise protocol

## 3. Core Components

### LoxationProfileManager
```swift
class LoxationProfileManager {
    // MARK: - Storage
    private var profiles: [String: LoxationProfile] = [:]  // peerID -> Profile
    private let profilesQueue = DispatchQueue(label: "loxation.profiles", attributes: .concurrent)
    
    // MARK: - Transfer Management
    private var incomingTransfers: [String: IncomingTransfer] = [:]
    private var outgoingTransfers: [String: OutgoingTransfer] = [:]
    private let transfersQueue = DispatchQueue(label: "loxation.transfers")
    
    // MARK: - Notifications
    let profileUpdates = PassthroughSubject<ProfileUpdate, Never>()
    let transferProgress = PassthroughSubject<TransferProgress, Never>()
    
    // MARK: - Configuration
    private let chunkSize: Int = 450
    private let maxTransferTime: TimeInterval = 30.0
    private let maxConcurrentTransfers = 10
}

private struct IncomingTransfer {
    let id: String
    let startTime: Date
    let senderId: String
    let queryType: LoxationQueryType
    var chunks: [UInt16: Data] = [:]
    let totalChunks: UInt16
    var receivedChunks: Set<UInt16> = []
    
    var isComplete: Bool {
        receivedChunks.count == totalChunks
    }
    
    var progress: Double {
        Double(receivedChunks.count) / Double(totalChunks)
    }
}

private struct OutgoingTransfer {
    let id: String
    let startTime: Date
    let recipientId: String
    let data: Data
    let chunks: [Data]
    var sentChunks: Set<UInt16> = []
    var acknowledgedChunks: Set<UInt16> = []
    
    var isComplete: Bool {
        acknowledgedChunks.count == chunks.count
    }
}
```

### Transfer State Tracking
```swift
struct ProfileUpdate {
    let peerID: String
    let profile: LoxationProfile
    let fields: Set<UpdateField>
    let timestamp: Date
}

struct TransferProgress {
    let transferId: String
    let peerID: String
    let progress: Double
    let isComplete: Bool
    let error: Error?
}
```

## 4. Implementation Phases

### Phase 1: Core Profile Support
Status: COMPLETE

1. Created LoxationProfile struct
   - Fields present with Codable conformance using AnyCodable for [String: Any]-like storage
   - Computed properties: serializedSize, needsChunking
   - Basic validation/sanitization helpers

2. Implemented LoxationProfileManager
   - In-memory storage and thread-safe access
   - Validation on setProfile, diff-based field update detection

3. Profile update notifications
   - profileUpdates PassthroughSubject publishes ProfileUpdate events

Deliverables implemented:
- LoxationProfile.swift
- LoxationProfileManager.swift
- Unit tests: pending

### Phase 2: Message Protocol
Status: PARTIAL COMPLETE

1. Message routing and handlers
   - LoxationMeshServiceExtensions.swift provides:
     handleLoxationMessage switch, handleLoxationAnnounce, handleLoxationQuery, handleLoxationData (compat for loxationChunk), handleLoxationComplete
   - Required BluetoothMeshService integration: route .loxationAnnounce/.loxationQuery/.loxationChunk/.loxationComplete to handleLoxationMessage (owner to wire; core file too large to auto-edit)

2. Query system
   - Query decode/validate implemented
   - Response generation for deviceInfo, userProfile, keyPackage, uwbToken, fullProfile
   - Privacy: deviceInfo may send clear; sensitive types attempt Noise encryption, otherwise fail gracefully

3. Profile announcements
   - Announce decode supported; updating LoxationProfile via setProfile
   - Rate limiting for announcements is handled by BluetoothMeshService core

Deliverables implemented:
- Message handlers in extension (core routing pending if not already wired)
- Query/response logic in extension
- Announcement handling

### Phase 3: Transfer Protocol (adapted to core fragmentation/ACKs)
Status: COMPLETE under “protocol-ACK-only” approach

Adaptation note: Instead of custom per-chunk protocol, rely on BitChat core fragmentation/reassembly and protocol ACK/backoff. Loxation uses a single logical envelope per transfer plus loxationComplete to mark end-of-transfer.

1. Chunking logic
   - Reused BitChat core transport fragmentation; LoxationDataEnvelope wraps entire response as payload
   - Integrity handled by core transport

2. Transfer state management
   - LoxationManagers tracks logical incoming/outgoing transfers (id, startTime, peer, queryType)
   - Timeout scanner runs every 2s; emits error progress and cleans state on exceed maxTransferTime

3. Progress monitoring
   - transferProgress PassthroughSubject publishes start (beginOutgoing), data-applied (applyLoxationData), completion (completeIncoming), and error/timeout
   - Bandwidth metrics at logical level via known envelope data length (coarse-grained)

4. Flow control
   - Soft concurrency placeholders in LoxationManagers; minimal enforcement without core send path changes
   - Pacing and per-peer priority queues can be added later if deeper integration is allowed

Deliverables implemented:
- Logical transfer state with timeout handling
- Progress monitoring via Combine
- Envelope-based flow leveraging core fragmentation/ACKs

Known limits (by design without core edits):
- No per-chunk ACK mapping or explicit chunk retries wired to Loxation; rely on transport-level retries/backoff
- Flow control is basic (soft caps). Full scheduler would require hooks in BluetoothMeshService

### Phase 4: BluetoothMeshService Integration
Status: PARTIAL (owner action required)

1. Packet handlers integration
   - Required: In BluetoothMeshService.handleReceivedPacket, add routing to extension:
     case .loxationAnnounce, .loxationQuery, .loxationChunk, .loxationComplete:
       self.handleLoxationMessage(messageType, packet: packet, from: peerID)
    **COMPLETED**

2. Noise encryption integration
   - Implemented in extension: sensitive responses attempt Noise encryption when a session exists

3. Broadcasting support
   - Extension uses broadcastPacket via loxationBroadcast shim for compatibility when targeted helpers are private

4. Caching/memory management
   - Profile caching is in LoxationProfileManager; advanced memory management can be added later

Deliverables pending:
- Ensure core routing to extension exists in BluetoothMeshService

### Phase 5: External Integrations
Status: NOT STARTED

1. UWB Token Integration
   - Protocol scaffold present; iOS service integration TBD

2. MLS Key Package Integration
   - To be integrated with MLSEncryptionService

3. Device ID Management
   - Stable deviceId currently taken from announce and sanitized; full lifecycle TBD

Deliverables pending:
- UWB hooks, MLS lifecycle, device ID management

## 6. Security Considerations
Status: IN PROGRESS

- Sensitive fields encryption preferred; fall back policy is “do not send” without Noise session
- Validation on incoming data; timeouts to avoid hanging transfers
- Rate limiting for announcements handled by core; further loxation-specific rate limiting TBD

## 7. Future Extensions
(no change)

## 8. Success Metrics
Status: PARTIAL

- Transmission success: relies on core transport; Loxation progress reports added
- Completion time: timeout is 30s; performance tuning TBD
- Memory usage: minimal footprint; advanced caps pending
- Zero data corruption: depends on core integrity; envelope decode guarded
- Cross-platform: maintained via envelope + core transport

### Phase 4: BluetoothMeshService Integration (Revised to leverage core fragmentation and existing reliability)
**Duration: 2-3 days**

Context
- Phase 3 now relies on BitChat’s built-in fragmentation/reassembly and transport reliability instead of custom LoxationChunk sequencing. Loxation uses a single logical “data envelope” plus loxationComplete to signal end-of-transfer, with minimal logical state and Combine progress events.

Goals
1. Tight integration with BluetoothMeshService dispatch
   - Ensure `handleReceivedPacket` routes loxation types: `.loxationAnnounce`, `.loxationQuery`, `.loxationChunk` (compat data), `.loxationComplete` to `handleLoxationMessage`.
   - Confirm correct BitchatPacket construction (senderID/recipientID/timestamp/ttl) and targeted vs broadcast paths use existing primitives (sendDirectToRecipient, sendViaSelectiveRelay, broadcastPacket) as appropriate.
   - Standardize logging via SecureLogger categories and ensure errors/warnings are deduplicated by existing rate-limiting.

2. Noise encryption policy for profile data
   - Define field-level policy:
     • Encrypted by default: keyPackage, userProfile.
     • Optional/clear: deviceId, locationId for announce/deviceInfo; uwbToken is NOT sensitive and can be sent clear.
   - Implement conditional encryption using existing NoiseEncryptionService:
     • For responses that require confidentiality (keyPackage, userProfile), wrap payload in Noise before packaging into BitchatPacket (i.e., use MessageType.noiseEncrypted inner flow when targeted).
     • For broadcast announcements (loxationAnnounce), keep clear minimal info; avoid large encrypted broadcasts.
   - Clarify access policy: targeted queries should be preferred for sensitive fields to leverage direct delivery + Noise.

3. Announcement and query orchestration
   - Announcements:
     • Trigger loxationAnnounce on peer connect and upon local profile updates with rate limiting (reuse existing dedupe/rate-control).
     • Keep payload minimal (deviceId + optional hints), avoid large broadcasts.
   - Query flows:
     • Introduce simple policy to auto-query userProfile or keyPackage upon first contact or when profile is stale.
     • Ensure each query uses the simplified transfer model: single data envelope + loxationComplete; rely on core fragmentation.

4. Progress and timeout surfacing
   - Wire LoxationManagers.shared.transferProgress to UI/ViewModel (subscription point), log progress steps (start/complete/error).
   - On timeout or decode errors, emit TransferProgress with error; ensure cleanup is idempotent.

5. Flow control alignment with core backpressure
   - Respect existing transport backpressure/rate limits; avoid sending bursts of loxation messages.
   - Soft cap concurrent logical transfers (maxConcurrentTransfers). For heavier usage, add a simple FIFO per-peer queue that starts when a slot frees.
   - Keep memory footprint bounded; rely on transport and existing BitChat memory pressure mechanisms.

6. Caching, invalidation, and memory
   - Maintain in-memory profile cache via LoxationProfileManager.
   - Invalidate/update cache on ProfileUpdate events.
   - Avoid duplicating large data blobs in multiple places; store only final profile state.

7. Telemetry and diagnostics
   - Add lightweight counters/metrics:
     • loxation queries sent/received by type
     • average logical transfer duration
     • timeout/error counts
   - Gate logs via SecureLogger levels to avoid noise.

Implementation checklist
- BluetoothMeshService:
  [ ] Ensure switch routing calls handleLoxationMessage for all loxation types
  [ ] Confirm BitchatPacket construction paths for targeted vs broadcast loxation messages
  [ ] Rate-limit announcements (reuse identity announce cadence)
  [ ] Prefer targeted, Noise-encrypted responses for sensitive fields
- LoxationMeshServiceExtensions:
  [ ] Keep data envelope path for loxationChunk compatibility and immediate apply
  [ ] Ensure loxationComplete always sent after data envelope on query responses
  [ ] Emit progress via LoxationManagers transferProgress at start/complete/error
- LoxationManagers:
  [ ] Keep minimal state + timeout scan (already implemented)
  [ ] Optionally add per-peer soft concurrency queue if needed by usage patterns
- UI/ViewModel:
  [ ] Subscribe to transferProgress for user-visible status (optional for Phase 4)
  [ ] Display minimal status for long transfers or errors

Deliverables
- Fully wired loxation handlers into BluetoothMeshService dispatch
- Field-level encryption policy applied using Noise for sensitive data on targeted queries
- Announcement + query orchestration with rate limiting
- Progress surfaced via Combine and bounded by timeouts
- Documentation updates to reflect simplified transport model and policies

Status update (continued)
- Verified that BluetoothMeshService.handleReceivedPacket routes .loxationAnnounce/.loxationQuery/.loxationChunk/.loxationComplete to handleLoxationMessage in LoxationMeshServiceExtensions.swift.
- Confirmed sendLoxationAnnounce(to:) is implemented in BluetoothMeshService with deduping via lastIdentityAnnounceTimes and identityAnnounceMinInterval.
- Confirmed use of broadcastPacket, sendDirectToRecipient, and sendViaSelectiveRelay are available to satisfy targeted vs broadcast delivery requirements.
- Noise encryption policy alignment: Targeted responses for sensitive fields should be encrypted and wrapped in MessageType.noiseEncrypted, leveraging NoiseEncryptionService present as noiseService.

Next tasks to complete Phase 4
1) LoxationMeshServiceExtensions
   - Ensure handleLoxationMessage implements:
     a) loxationAnnounce: decode and setProfile via LoxationProfileManager, minimal payload only.
     b) loxationQuery: policy-gated responses; for sensitive fields (userProfile), attempt Noise encryption if noiseService.hasEstablishedSession(with: requesterID), else skip sending.
     c) loxationChunk compatibility path: treat as envelope data per Phase 3; immediately apply to manager and emit progress.
     d) loxationComplete: finalize logical transfer and emit completion.
   - Always send loxationComplete after any single-envelope data response.

2) BluetoothMeshService glue points
   - After version negotiation and identity flows, on initial peer contact, schedule lightweight auto-query orchestration:
     • Prefer deviceInfo via broadcast or direct only if profile is unknown.
     • For sensitive fields (userProfile/keyPackage), schedule targeted queries only if Noise session is established; otherwise defer until after handshake.
   - Rate-limit loxationAnnounce alongside identity announcements. Existing sendLoxationAnnounce satisfies this; add call sites:
     • On rotatePeerID(): already calls sendLoxationAnnounce().
     • On startServices(): optionally send initial loxationAnnounce after general announce (can be gated by dedupe).
     • On local profile update event: subscribe to LoxationProfileManager.profileUpdates and post minimal loxationAnnounce.

3) Progress/timeout surfacing
   - Expose LoxationProfileManager.shared.transferProgress to ChatViewModel subscription point for optional UI display.
   - Log progress at SecureLogger.session level with throttling.

4) Flow control alignment
   - Respect existing backpressure via send* helpers and aggregation.
   - Enforce maxConcurrentTransfers in LoxationProfileManager; queuing is optional for Phase 4.

5) Telemetry hooks
   - Increment counters for queries sent/received and transfer durations in extension; gate logs.

Acceptance criteria
- Receiving loxationAnnounce updates local profile cache without crashes; de-duplicated by manager.
- Responding to loxationQuery sends a single logical envelope plus loxationComplete; for sensitive fields, response is sent only when Noise session is established.
- handleReceivedPacket switch continues to route all loxation message types to the extension.
- No regressions to ACK/fragmentation paths; large profile payloads travel using core fragmentation.
- Logs show progress start/complete and timeouts within LoxationProfileManager as transfers occur.

Test plan
- Unit: Validate manager setProfile diff and update events; needsChunking threshold; timeout scanner emits error.
- Integration: Simulate:
  • loxationAnnounce ingest path.
  • loxationQuery for deviceInfo (clear) succeeds.
  • loxationQuery for userProfile without Noise is withheld; with Noise session established, succeeds and emits loxationComplete.
  • Large userProfile triggers fragmentation and still completes.
- E2E: Two peers exchange announcements; auto-query runs; UI subscribes to progress optionally.

Notes
- Do not send large encrypted broadcasts. Keep loxationAnnounce minimal.
- Prefer targeted delivery for sensitive data leveraging Noise.
- Defer complex scheduling/backpressure to core; only minimal logical caps within LoxationProfileManager.

### Phase 5: External Integrations
**Duration: 2-3 days**

1. **UWB Token Integration**
   ```swift
   // Protocol for future UWBService integration
   protocol UWBServiceDelegate: AnyObject {
       func uwbTokenDidUpdate(_ token: String)
       func uwbTokenDidExpire()
       func uwbServiceDidBecomeAvailable()
   }
   ```

2. **MLS Key Package Integration**
   - Integration with existing MLSEncryptionService
   - Automatic key package generation and updates
   - Key package validation and lifecycle management
   - Treat keyPackages with the same sensitivity and exposure policy as public keys (not confidential data), but still validate format and integrity before distribution

3. **Device ID Management**
   - Stable device identifier generation and persistence
   - Device ID validation and collision detection
   - Cross-session identifier consistency

**Deliverables:**
- UWB token integration hooks and protocols
- MLS key package handling and lifecycle
- Robust device ID management system

## 6. Security Considerations

### Data Protection
- Encrypt sensitive fields (keyPackage, userProfile) with Noise
- Validate all incoming data
- Rate limit profile requests
- Implement transfer timeouts

### Privacy Controls
- Optional profile sharing
- Field-level privacy settings
- Query filtering based on peer trust
- Audit logging for profile access

## 7. Future Extensions

### UWB Integration
- Real-time location tracking
- Proximity-based profile sharing
- Spatial mesh optimization

### MLS Group Management
- Automatic group formation
- Key package distribution
- Group member discovery

### Advanced Features
- Profile synchronization
- Conflict resolution
- Version control
- Backup and restore

## 8. Success Metrics

- Profile transmission success rate > 95%
- Transfer completion time < 10 seconds
- Memory usage < 50MB for 100 peers
- Zero data corruption incidents
- Consistent cross-platform operation

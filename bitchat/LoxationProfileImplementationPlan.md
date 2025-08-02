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
    case loxationAnnounce = 0x20      // Profile announcement
    case loxationQuery = 0x21         // Request profile data
    case loxationChunk = 0x22         // Profile chunk data
    case loxationComplete = 0x23      // Transfer completion
    case loxationUpdate = 0x24        // Field update notification
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
**Duration: 1-2 days**

1. **Create LoxationProfile struct**
   - Add all required fields
   - Implement Codable conformance with custom handling for [String: Any]
   - Add computed properties for chunking

2. **Implement LoxationProfileManager**
   - Basic profile storage and retrieval
   - Thread-safe operations with concurrent queues
   - Profile validation and sanitization

3. **Add profile update notifications**
   - Combine publishers for updates
   - Event types for different changes
   - Change detection logic

**Deliverables:**
- LoxationProfile.swift
- LoxationProfileManager.swift
- Unit tests for profile operations

### Phase 2: Message Protocol
**Duration: 2-3 days**

1. **Add message type handlers to BluetoothMeshService**
   ```swift
   private func handleLoxationAnnounce(_ packet: BitchatPacket, from peerID: String)
   private func handleLoxationQuery(_ packet: BitchatPacket, from peerID: String) 
   private func handleLoxationChunk(_ packet: BitchatPacket, from peerID: String)
   private func handleLoxationComplete(_ packet: BitchatPacket, from peerID: String)
   private func handleLoxationUpdate(_ packet: BitchatPacket, from peerID: String)
   ```

2. **Implement query system**
   - Query message creation and validation
   - Response generation based on query type
   - Query routing and filtering for privacy

3. **Add profile announcements**
   - Automatic announcements on peer connect
   - Triggered announcements on profile updates
   - Rate limiting to prevent spam

**Deliverables:**
- Message handlers in BluetoothMeshService
- Query/response system implementation
- Profile announcement logic with rate limiting

### Phase 3: Chunked Transfer Protocol
**Duration: 3-4 days**

1. **Implement chunking logic**
   ```swift
   func chunkProfile(_ profile: LoxationProfile, transferId: String) -> [LoxationChunk]
   func reassembleChunks(_ chunks: [LoxationChunk]) throws -> LoxationProfile
   func validateChunkIntegrity(_ chunk: LoxationChunk) -> Bool
   ```

2. **Add transfer state management**
   - Track incoming/outgoing transfers with UUIDs
   - Handle transfer timeouts and cleanup
   - Implement retry logic with exponential backoff

3. **Add progress monitoring**
   - Transfer progress events via Combine
   - Completion and error notifications
   - Bandwidth usage tracking

4. **Implement flow control**
   - Concurrent transfer limits per peer
   - Priority queuing for different query types
   - Memory management for large transfers

**Deliverables:**
- Chunking/reassembly system with integrity checks
- Transfer state management with timeout handling
- Progress monitoring and flow control

### Phase 4: BluetoothMeshService Integration
**Duration: 2-3 days**

1. **Add packet handlers**
   - Integration with existing message dispatch in `handleReceivedPacket`
   - Add Loxation message types to switch statement
   - Proper error handling and logging

2. **Integrate with Noise encryption**
   - Encrypt sensitive profile data (keyPackage, userProfile)
   - Handle encrypted chunk transmission
   - Key exchange management for profile access

3. **Add broadcasting support**
   - Profile announcements to all connected peers
   - Selective profile sharing based on privacy settings
   - Efficient broadcast mechanisms

4. **Implement caching and memory management**
   - In-memory profile caching with LRU eviction
   - Cache invalidation on profile updates
   - Memory pressure handling

**Deliverables:**
- Full BluetoothMeshService integration
- Noise encryption support for sensitive data
- Broadcasting and caching with memory management

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

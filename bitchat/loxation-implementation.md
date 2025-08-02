# Loxation Profile Implementation Plan

## 1. Core Data Structures

### LoxationProfile
```swift
struct LoxationProfile: Codable {
    // Core Identity
    let deviceId: String
    let locationId: String?
    
    // Tokens & Keys
    let uwbToken: String?
    let keyPackage: String?  // Base64 encoded MLS key package
    
    // User Data
    let userProfile: [String: Any]
    
    // Metadata
    let timestamp: Date
    let version: UInt8 = 1
}
```

## 2. Message Protocol

### Message Types
```swift
enum LoxationMessageType: UInt8 {
    case announce = 0x01    // Basic profile announcement
    case query = 0x02       // Request profile data
    case chunk = 0x03       // Profile chunk data
    case complete = 0x04    // Final chunk marker
    case update = 0x05      // Profile field updates
}
```

### Query Types
```swift
enum LoxationQueryType: UInt8 {
    case fullProfile = 0x01
    case deviceInfo = 0x02    // deviceId + locationId
    case keyPackage = 0x03    // MLS key package only
    case userProfile = 0x04   // Custom JSON data
}
```

## 3. Components

### LoxationProfileManager
- In-memory profile storage
- Profile update notifications
- Chunked transfer handling
- Query processing

### Transfer Protocol
- Chunk size: 450 bytes
- UUID-based transfer tracking
- Automatic reassembly
- Progress monitoring

## 4. Implementation Phases

### Phase 1: Core Profile Support
1. Add LoxationProfile struct
2. Implement profile manager
3. Add profile storage/retrieval
4. Setup update notifications

### Phase 2: Message Protocol
1. Add message type handlers
2. Implement query system
3. Add profile announcements
4. Setup update broadcasting

### Phase 3: Transfer Protocol
1. Implement chunking logic
2. Add reassembly system
3. Add transfer tracking
4. Implement timeouts

### Phase 4: BluetoothMeshService Integration
1. Add packet handlers
2. Integrate with noise encryption
3. Add UWB token support
4. Setup MLS integration

## 5. Detailed Implementation Steps

### Step 1: Profile Manager
```swift
class LoxationProfileManager {
    // Storage
    private var profiles: [String: LoxationProfile] = [:]
    
    // Updates
    let updates = PassthroughSubject<ProfileUpdate, Never>()
    
    // Transfer tracking
    private var transfers: [String: TransferState] = [:]
}
```

### Step 2: Transfer Protocol
```swift
struct TransferState {
    let id: String
    let startTime: Date
    let type: TransferType
    var chunks: [Int: Data]
    let total: Int
    
    var isComplete: Bool {
        chunks.count == total
    }
}
```

### Step 3: Message Handlers
```swift
extension BluetoothMeshService {
    func handleLoxationMessage(_ packet: BitchatPacket) {
        switch packet.type {
        case .announce: handleAnnounce(packet)
        case .query: handleQuery(packet)
        case .chunk: handleChunk(packet)
        case .complete: handleComplete(packet)
        case .update: handleUpdate(packet)
        }
    }
}
```

### Step 4: Profile Updates
```swift
struct ProfileUpdate {
    let peerID: String
    let field: UpdateField
    let value: Any
    let timestamp: Date
}
```

## 6. Testing Strategy

### Unit Tests
1. Profile encoding/decoding
2. Chunk splitting/reassembly
3. Query handling
4. Update notifications

### Integration Tests
1. Profile transmission
2. MLS key package handling
3. UWB token integration
4. Full profile updates

## 7. Security Considerations

1. Profile validation
2. Transfer authentication
3. Update verification
4. Rate limiting


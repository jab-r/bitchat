// LoxationProfile.swift
// bitchat
//
// Phase 1: Core data structures for Loxation Profile
//
// Notes:
// - userProfile uses [String: AnyCodable] to support arbitrary JSON
// - Provides binary size estimation and chunking threshold helpers
// - Includes minimal validators/sanitizers

import Foundation

// Lightweight AnyCodable to allow [String: Any]-like Codable storage
public struct AnyCodable: Codable, Equatable, Hashable {
    public let value: Any

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (let l as NSNull, let r as NSNull):
            return true
        case (let l as Bool, let r as Bool):
            return l == r
        case (let l as Int, let r as Int):
            return l == r
        case (let l as Double, let r as Double):
            return l == r
        case (let l as String, let r as String):
            return l == r
        case (let l as [Any], let r as [Any]):
            let la = l.map { AnyCodable($0) }
            let ra = r.map { AnyCodable($0) }
            return la == ra
        case (let l as [String: Any], let r as [String: Any]):
            let ld = l.mapValues { AnyCodable($0) }
            let rd = r.mapValues { AnyCodable($0) }
            return ld == rd
        case (let l as Data, let r as Data):
            return l == r
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch value {
        case is NSNull:
            hasher.combine(0 as UInt8)
        case let b as Bool:
            hasher.combine(1 as UInt8); hasher.combine(b)
        case let i as Int:
            hasher.combine(2 as UInt8); hasher.combine(i)
        case let d as Double:
            hasher.combine(3 as UInt8); hasher.combine(d)
        case let s as String:
            hasher.combine(4 as UInt8); hasher.combine(s)
        case let arr as [Any]:
            hasher.combine(5 as UInt8)
            for v in arr { hasher.combine(AnyCodable(v)) }
        case let dict as [String: Any]:
            hasher.combine(6 as UInt8)
            // Order-independent hashing: sort keys
            for key in dict.keys.sorted() {
                hasher.combine(key)
                hasher.combine(AnyCodable(dict[key] as Any))
            }
        case let data as Data:
            hasher.combine(7 as UInt8); hasher.combine(data)
        default:
            hasher.combine(255 as UInt8)
            hasher.combine(String(describing: value))
        }
    }

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            self.value = b
        } else if let i = try? container.decode(Int.self) {
            self.value = i
        } else if let i8 = try? container.decode(Int8.self) {
            self.value = Int(i8)
        } else if let i16 = try? container.decode(Int16.self) {
            self.value = Int(i16)
        } else if let i32 = try? container.decode(Int32.self) {
            self.value = Int(i32)
        } else if let i64 = try? container.decode(Int64.self) {
            self.value = Int(i64)
        } else if let u = try? container.decode(UInt.self) {
            self.value = Int(u)
        } else if let u8 = try? container.decode(UInt8.self) {
            self.value = Int(u8)
        } else if let u16 = try? container.decode(UInt16.self) {
            self.value = Int(u16)
        } else if let u32 = try? container.decode(UInt32.self) {
            self.value = Int(u32)
        } else if let u64 = try? container.decode(UInt64.self) {
            self.value = Int(u64)
        } else if let d = try? container.decode(Double.self) {
            self.value = d
        } else if let s = try? container.decode(String.self) {
            self.value = s
        } else if let a = try? container.decode([AnyCodable].self) {
            self.value = a.map { $0.value }
        } else if let d = try? container.decode([String: AnyCodable].self) {
            var dict: [String: Any] = [:]
            for (k, v) in d {
                dict[k] = v.value
            }
            self.value = dict
        } else if let data = try? container.decode(Data.self) {
            self.value = data
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported AnyCodable value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let b as Bool:
            try container.encode(b)
        case let i as Int:
            try container.encode(i)
        case let d as Double:
            try container.encode(d)
        case let s as String:
            try container.encode(s)
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]:
            var enc: [String: AnyCodable] = [:]
            for (k, v) in dict { enc[k] = AnyCodable(v) }
            try container.encode(enc)
        case let data as Data:
            try container.encode(data)
        default:
            // Fallback to string description
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Loxation Core Types

public enum LoxationQueryType: UInt8, Codable {
    case fullProfile = 0x01
    case deviceInfo  = 0x02
    case keyPackage  = 0x03
    case userProfile = 0x04
    case uwbToken    = 0x05
}

public enum UpdateField: String, Codable, CaseIterable, Hashable {
    case locationId
    case uwbToken
    case keyPackage
    case userProfile
}

public struct LoxationChunk: Codable, Equatable {
    public let transferId: String
    public let chunkIndex: UInt16
    public let totalChunks: UInt16
    public let data: Data
    public let checksum: UInt32
}

public struct LoxationQuery: Codable, Equatable {
    public let queryType: LoxationQueryType
    public let requesterId: String
    public let transferId: String
    public let timestamp: Date
}

public struct LoxationUpdate: Codable, Equatable {
    public let field: UpdateField
    public let value: Data
    public let timestamp: Date
    public let signature: Data?
}

// MARK: - LoxationProfile

public struct LoxationProfile: Codable, Equatable {
    // Core Identity
    public let deviceId: String        // Stable device identifier (8-64 hex chars recommended)
    public let locationId: String?     // Optional location identifier

    // Tokens & Keys
    public let uwbToken: String?       // UWB token from future UWBService
    public let keyPackage: String?     // Base64 encoded MLS key package

    // Arbitrary JSON profile data
    public let userProfile: [String: AnyCodable]

    // Metadata
    public let timestamp: Date         // Last update timestamp
    public let version: UInt8          // Protocol/control version

    public init(deviceId: String,
                locationId: String? = nil,
                uwbToken: String? = nil,
                keyPackage: String? = nil,
                userProfile: [String: AnyCodable] = [:],
                timestamp: Date = Date(),
                version: UInt8 = 1) {
        self.deviceId = LoxationProfile.sanitizeDeviceId(deviceId)
        self.locationId = locationId?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.uwbToken = uwbToken
        self.keyPackage = keyPackage
        self.userProfile = userProfile
        self.timestamp = timestamp
        self.version = version
    }

    // Computed properties
    public var serializedSize: Int {
        (try? JSONEncoder().encode(self))?.count ?? 0
    }

    public var needsChunking: Bool {
        // Allow headroom for packet headers, padding, encryption tags, etc.
        serializedSize > 450
    }

    // Minimal validation helpers
    public static func sanitizeDeviceId(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func isValid() -> Bool {
        // Device ID required, modest length checks
        !deviceId.isEmpty && deviceId.count <= 128
    }
}

// MARK: - Profile/Transfer Update Events

public struct ProfileUpdate: Equatable {
    public let peerID: String
    public let profile: LoxationProfile
    public let fields: Set<UpdateField>
    public let timestamp: Date
}

public struct TransferProgress: Equatable {
    public let transferId: String
    public let peerID: String
    public let progress: Double
    public let isComplete: Bool
    public let error: Error?

    public static func == (lhs: TransferProgress, rhs: TransferProgress) -> Bool {
        return lhs.transferId == rhs.transferId &&
               lhs.peerID == rhs.peerID &&
               lhs.progress == rhs.progress &&
               lhs.isComplete == rhs.isComplete &&
               ((lhs.error == nil && rhs.error == nil) ||
                (lhs.error.map { String(describing: $0) } == rhs.error.map { String(describing: $0) }))
    }
}

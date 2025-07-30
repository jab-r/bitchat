import Foundation
import CoreBluetooth

/// Service to transmit MLS KeyPackages over BLE by chunking and reassembly.
class MLSKeyPackageTransmissionService: NSObject {
    private let mtu: Int = 185  // Approximate safe MTU for BLE writes
    private var receiveBuffers: [CBPeripheral: Data] = [:]
    private var expectedLengths: [CBPeripheral: Int] = [:]

    /// Send a KeyPackage Data to a peripheral via the specified characteristic.
    func sendKeyPackage(_ package: Data, to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let totalLength = package.count
        // Prepend 4-byte big-endian header indicating total length
        var header = withUnsafeBytes(of: UInt32(totalLength).bigEndian) { Data($0) }
        let fullData = header + package
        var offset = 0
        while offset < fullData.count {
            let chunkSize = min(mtu, fullData.count - offset)
            let chunk = fullData.subdata(in: offset..<offset + chunkSize)
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            offset += chunkSize
        }
    }

    /// Call this when receiving characteristic updates to accumulate KeyPackage data.
    func didReceiveData(_ data: Data, from peripheral: CBPeripheral) {
        if let expected = expectedLengths[peripheral] {
            // Continuing to read body
            var buffer = receiveBuffers[peripheral] ?? Data()
            buffer.append(data)
            receiveBuffers[peripheral] = buffer
            if buffer.count >= expected {
                let packageData = buffer.prefix(expected)
                NotificationCenter.default.post(
                    name: .didReceiveKeyPackage,
                    object: packageData,
                    userInfo: ["peripheral": peripheral]
                )
                receiveBuffers[peripheral] = nil
                expectedLengths[peripheral] = nil
            }
        } else {
            // Reading header
            var headerData = receiveBuffers[peripheral] ?? Data()
            headerData.append(data)
            if headerData.count >= 4 {
                let header = headerData.prefix(4)
                let length = Int(UInt32(bigEndian: header.withUnsafeBytes { $0.load(as: UInt32.self) }))
                expectedLengths[peripheral] = length
                let remainder = headerData.dropFirst(4)
                receiveBuffers[peripheral] = Data(remainder)
                if length == 0 {
                    NotificationCenter.default.post(
                        name: .didReceiveKeyPackage,
                        object: Data(),
                        userInfo: ["peripheral": peripheral]
                    )
                    receiveBuffers[peripheral] = nil
                    expectedLengths[peripheral] = nil
                }
            } else {
                receiveBuffers[peripheral] = headerData
            }
        }
    }
}

extension Notification.Name {
    static let didReceiveKeyPackage = Notification.Name("MLSKeyPackageTransmissionServiceDidReceiveKeyPackage")
}
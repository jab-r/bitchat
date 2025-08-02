 // UWBDiscoveryService.swift
 // bitchat
 //
 // Native NearbyInteraction-based service to obtain the UWB discovery token
 // and publish it into LoxationProfileManager. Mirrors ../loxation/UWBModule.getDiscoveryToken.
 //
 // Notes:
 // - Returns a base64-encoded NSKeyedArchiver encoded NIDiscoveryToken (same as sibling project).
 // - Lightweight: initialize() sets up NISession, getDiscoveryToken() fetches token,
 //   refreshToken() re-fetches and updates profile field automatically.
 // - Compiles on macOS by providing a no-op implementation (NearbyInteraction is iOS-only).
 // - Consumers can also subscribe to tokenPublisher if needed.

 import Foundation
 import Combine

 #if canImport(NearbyInteraction) && os(iOS)
 import NearbyInteraction

 @MainActor
 final class UWBDiscoveryService: NSObject, NISessionDelegate {
     static let shared = UWBDiscoveryService()

     private var session: NISession?
     private var isInitialized = false

     private let profileManager = LoxationProfileManager()
     private let deviceId = DeviceIDManager.shared.getOrCreateDeviceId()

     // Publish token updates (base64) for observers
     let tokenPublisher = PassthroughSubject<String?, Never>()

     private override init() {
         super.init()
     }

     // MARK: - Public API

     func initialize() {
         guard !isInitialized else { return }
         guard NISession.isSupported else {
             SecureLogger.log("UWB not supported on this device", category: SecureLogger.security, level: .info)
             return
         }
         let s = NISession()
         s.delegate = self
         self.session = s
         self.isInitialized = true
     }

     /// Returns the current discovery token as a base64-encoded string, or nil if unavailable.
     func getDiscoveryToken() -> String? {
         guard let token = session?.discoveryToken else { return nil }
         return encodeDiscoveryToken(token)
     }

     /// Refresh (re-fetch) the token and update profile automatically on success.
     func refreshToken() {
         if let tokenB64 = getDiscoveryToken() {
             applyToken(tokenB64)
         } else {
             if !isInitialized { initialize() }
             if let tokenB64 = getDiscoveryToken() {
                 applyToken(tokenB64)
             } else {
                 SecureLogger.log("UWB discovery token unavailable", category: SecureLogger.security, level: .debug)
             }
         }
     }

     // MARK: - Private

     private func applyToken(_ tokenB64: String) {
         tokenPublisher.send(tokenB64)
         profileManager.updateField(for: deviceId, field: .uwbToken, value: tokenB64)
     }

     private func encodeDiscoveryToken(_ token: NIDiscoveryToken) -> String? {
         do {
             let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
             return data.base64EncodedString()
         } catch {
             SecureLogger.logError(error, context: "UWBDiscoveryService.encodeDiscoveryToken", category: SecureLogger.security)
             return nil
         }
     }

     // MARK: - NISessionDelegate

     func session(_ session: NISession, didInvalidateWith error: Error) {
         SecureLogger.log("UWB session invalidated: \(error.localizedDescription)", category: SecureLogger.security, level: .warning)
         self.isInitialized = false
         self.session = nil
     }

     func sessionWasSuspended(_ session: NISession) {
         SecureLogger.log("UWB session suspended", category: SecureLogger.security, level: .info)
     }

     func sessionSuspensionEnded(_ session: NISession) {
         SecureLogger.log("UWB session suspension ended", category: SecureLogger.security, level: .info)
         refreshToken()
     }
 }
 #else

 // macOS/no-NearbyInteraction stub for build compatibility
 final class UWBDiscoveryService {
     static let shared = UWBDiscoveryService()

     // Keep API identical; token publishing is a no-op on non-iOS.
     let tokenPublisher = PassthroughSubject<String?, Never>()

     private init() {}

     func initialize() {
         // no-op
     }

     func getDiscoveryToken() -> String? {
         return nil
     }

     func refreshToken() {
         // no-op
     }
 }
 #endif

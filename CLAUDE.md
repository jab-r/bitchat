# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BitChat is a decentralized peer-to-peer messaging app that operates over Bluetooth mesh networks without requiring internet connectivity. It's a native iOS/macOS SwiftUI application that implements:

- **Bluetooth LE mesh networking** with automatic peer discovery and multi-hop message relay
- **End-to-end encryption** using the Noise Protocol Framework (XX pattern) for private messages
- **Binary protocol** optimized for Bluetooth LE with compact packet format and TTL-based routing
- **Store-and-forward messaging** for offline peers
- **Universal app** supporting both iOS 16.0+ and macOS 13.0+

## Build Commands

### Using XcodeGen (Primary method)
```bash
# Generate Xcode project from project.yml
xcodegen generate

# Open the generated project
open bitchat.xcodeproj
```

### Using just (macOS development)
```bash
# Build and run on macOS (handles temporary modifications)
just run

# Build only
just build

# Clean and restore original files
just clean

# Check prerequisites
just check
```

### Using Swift Package Manager
```bash
# Open as Swift package
open Package.swift
```

### Testing
```bash
# Run tests through Xcode after generating project
# Test targets: bitchatTests_iOS, bitchatTests_macOS
```

## Architecture

### Core Components

- **BitchatApp.swift**: Main SwiftUI app entry point
- **ContentView.swift**: Primary chat interface
- **ChatViewModel.swift**: Main view model handling chat state

### Protocol Implementation
- **Protocols/**: Binary protocol, BitChat protocol, encoding utilities
- **Noise/**: Noise Protocol Framework implementation for encryption
- **Nostr/**: Nostr protocol integration for identity management

### Services Layer
- **BluetoothMeshService.swift**: Core Bluetooth mesh networking
- **MessageRouter.swift**: Message routing and relay logic
- **MLSEncryptionService.swift**: MLS group encryption
- **NoiseEncryptionService.swift**: Noise Protocol encryption
- **DeliveryTracker.swift**: Message delivery tracking
- **MessageRetryService.swift**: Retry logic for failed messages

### Models
- **BitchatPeer.swift**: Peer representation and state
- **PeerSession.swift**: Session management

### Utilities
- **OptimizedBloomFilter.swift**: Memory-efficient duplicate detection
- **LRUCache.swift**: Caching implementation
- **CompressionUtil.swift**: LZ4 message compression
- **BatteryOptimizer.swift**: Power management

### Testing Structure
- **EndToEnd/**: E2E tests for private and public chat scenarios
- **Integration/**: Integration tests
- **Mocks/**: Mock implementations for testing

## Key Technical Details

### Project Configuration
- Uses **XcodeGen** with `project.yml` for project generation
- Supports both iOS and macOS targets with shared codebase
- Dependencies: P256K (secp256k1), MLS (Message Layer Security)
- Share Extension included for iOS

### Protocol Stack
1. **Transport Layer**: Bluetooth LE
2. **Encryption Layer**: Noise Protocol Framework
3. **Session Layer**: Message framing and state management
4. **Application Layer**: BitChat application protocol

### Binary Protocol Features
- 1-byte type field for compact packets
- TTL-based routing (max 7 hops)
- Automatic fragmentation for large messages
- Message deduplication via unique IDs

### Security
- **Private messages**: Noise Protocol XX pattern with forward secrecy
- **Identity management**: Nostr-based identity with key derivation
- **Emergency wipe**: Triple-tap logo for instant data clearing
- **Cover traffic**: Timing obfuscation and dummy messages

## Development Notes

- **No internet required**: All communication is device-to-device
- **Physical device required**: Bluetooth functionality needs real hardware
- **Platform-specific**: iOS uses LaunchScreen.storyboard, macOS builds exclude it
- **Clean architecture**: Clear separation between networking, encryption, and UI layers
- **Performance optimized**: LZ4 compression, bloom filters, adaptive battery modes

## Dependencies

External packages are managed through Swift Package Manager:
- **P256K**: secp256k1 cryptographic operations
- **MLS**: Message Layer Security framework (local binary)

The project uses a custom MLS binary framework located in `MLSBinary/` for advanced group encryption capabilities.
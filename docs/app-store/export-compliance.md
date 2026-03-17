# LoadScan Export Compliance Statement

Date: 2026-03-17
App: LoadScan
Bundle: `$(PRODUCT_BUNDLE_IDENTIFIER)`
Reviewed build context: iOS app source in `/Users/alainfumero/Documents/IOSapp`

## Summary

LoadScan uses encryption only through Apple's built-in operating system frameworks and services. Based on the current implementation, LoadScan does not implement or include proprietary cryptographic algorithms, and it does not use third-party cryptographic libraries outside Apple's operating system.

## Encryption Used

- HTTPS/TLS network connections made through Apple's `URLSession`
- App Store purchase and receipt flows handled by Apple's `StoreKit`
- Sign in with Apple nonce hashing handled by Apple's `CryptoKit`
- Apple biometric authentication handled by Apple's `LocalAuthentication`

## Encryption Not Used

- No custom encryption protocols
- No proprietary cryptographic algorithms
- No third-party encryption libraries such as OpenSSL
- No VPN, MDM, or traffic-tunneling functionality
- No end-to-end messaging or user-controlled file encryption features

## App Store Connect Statement

LoadScan uses encryption limited to that provided within the Apple operating system. The app relies on Apple's standard networking and authentication frameworks for HTTPS/TLS transport security, Sign in with Apple, StoreKit purchases, and biometric authentication. The app does not implement non-exempt encryption and does not require export compliance documentation upload in App Store Connect.

## Recommended App Store Connect Response

- `ITSAppUsesNonExemptEncryption`: `NO`
- If App Store Connect asks whether the app uses non-exempt encryption: `No`
- If Apple requests clarification, provide the App Store Connect statement above

## Code Basis Reviewed

- `ApplianceManifest/Services/Infrastructure.swift` uses `URLSession`
- `ApplianceManifest/Services/SubscriptionService.swift` uses `StoreKit`
- `ApplianceManifest/Views/AuthView.swift` uses `CryptoKit` only for Sign in with Apple nonce hashing
- `ApplianceManifest/ApplianceManifest.entitlements` enables Sign in with Apple

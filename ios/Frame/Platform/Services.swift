import AVFoundation
import CoreLocation
import Foundation
import Photos
import Security
import UIKit

// MARK: - Photo library

enum SaveError: LocalizedError {
    case denied
    var errorDescription: String? {
        "frame needs permission to add photos. Turn it on in Settings, Privacy, Photos."
    }
}

enum PhotoSaver {
    static let albumName = "frame"

    /// Saves the photo exactly as captured (HEIC or JPEG data) with its location. With full access it also
    /// files it in a "frame" album; otherwise it lands in Recents only. Returns true when it went into the album.
    @discardableResult
    static func save(_ data: Data, location: CLLocation?) async throws -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized:
            let album = findAlbum()
            try await PHPhotoLibrary.shared().performChanges {
                let request = makeRequest(data, location: location)
                guard let placeholder = request.placeholderForCreatedAsset else { return }
                if let album, let change = PHAssetCollectionChangeRequest(for: album) {
                    change.addAssets([placeholder] as NSArray)
                } else {
                    let create = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                    create.addAssets([placeholder] as NSArray)
                }
            }
            return true
        case .limited:
            try await PHPhotoLibrary.shared().performChanges { _ = makeRequest(data, location: location) }
            return false
        default:
            let addOnly = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard addOnly == .authorized || addOnly == .limited else { throw SaveError.denied }
            try await PHPhotoLibrary.shared().performChanges { _ = makeRequest(data, location: location) }
            return false
        }
    }

    private static func makeRequest(_ data: Data, location: CLLocation?) -> PHAssetCreationRequest {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: data, options: nil)
        request.creationDate = Date()
        if let location { request.location = location }
        return request
    }

    private static func findAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
    }
}

// MARK: - Keychain

enum KeychainStore {
    private static let service = "com.eitanshay.frame"
    private static let account = "gemini-api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    static func write(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = baseQuery
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Voice

/// Speaks coaching lines over any music, ducking it briefly.
final class Voice {
    private let synth = AVSpeechSynthesizer()
    private var configured = false

    func say(_ text: String, interrupt: Bool = false) {
        if !configured {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
            configured = true
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        if interrupt && synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.08
        u.prefersAssistiveTechnologySettings = true
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func shutter() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func ready() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

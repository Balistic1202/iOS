import Foundation
import Observation

protocol Persistence {
    func load() throws -> AppData?
    func save(_ data: AppData) throws
    func erase() throws
}

enum AppCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Stores everything in one JSON file inside the app's own container. Nothing leaves the device.
struct FilePersistence: Persistence {
    let url: URL

    static var standard: FilePersistence {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FilePersistence(url: folder.appendingPathComponent("health-companion.json"))
    }

    func load() throws -> AppData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try AppCoding.decoder().decode(AppData.self, from: Data(contentsOf: url))
    }

    func save(_ data: AppData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AppCoding.encoder().encode(data).write(to: url, options: [.atomic, .completeFileProtection])
    }

    func erase() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

final class MemoryPersistence: Persistence {
    var stored: AppData?
    func load() throws -> AppData? { stored }
    func save(_ data: AppData) throws { stored = data }
    func erase() throws { stored = nil }
}

@MainActor
@Observable
final class AppStore {
    private(set) var data: AppData
    private(set) var lastError: String?
    private let persistence: Persistence

    init(persistence: Persistence) {
        self.persistence = persistence
        do {
            data = try persistence.load() ?? .empty
        } catch {
            data = .empty
            lastError = "Saved data could not be read."
        }
    }

    var profile: Profile? { data.profile }

    var decisionsNewestFirst: [SavedDecision] { data.decisions.sorted { $0.timestamp > $1.timestamp } }
    var checkInsNewestFirst: [CheckIn] { data.checkIns.sorted { $0.timestamp > $1.timestamp } }

    func assessment(for decision: SavedDecision) -> Assessment? {
        data.assessments.first { $0.id == decision.assessmentID }
    }

    // MARK: Changes. Each one is an explicit user action.

    func saveProfile(goals: [Goal], dietaryPreferences: [DietaryPreference], allergies: AllergyRecord, now: Date = .now) {
        data.profile = Profile(goals: goals, dietaryPreferences: dietaryPreferences, allergies: allergies,
                               consentVersion: Profile.currentConsentVersion, updatedAt: now)
        persist()
    }

    /// Stores the assessment snapshot together with the user's chosen action. Never called automatically.
    @discardableResult
    func saveDecision(assessment: Assessment, action: DecisionAction, now: Date = .now) -> SavedDecision {
        if !data.assessments.contains(where: { $0.id == assessment.id }) {
            data.assessments.append(assessment)
        }
        let decision = SavedDecision(id: UUID(), assessmentID: assessment.id, action: action, timestamp: now)
        data.decisions.append(decision)
        persist()
        return decision
    }

    func deleteDecision(_ decision: SavedDecision) {
        data.decisions.removeAll { $0.id == decision.id }
        if !data.decisions.contains(where: { $0.assessmentID == decision.assessmentID }) {
            data.assessments.removeAll { $0.id == decision.assessmentID }
        }
        persist()
    }

    func addCheckIn(energy: Int, manageability: Int, note: String, now: Date = .now) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        data.checkIns.append(CheckIn(id: UUID(), timestamp: now, energy: energy, manageability: manageability,
                                     note: trimmed.isEmpty ? nil : trimmed))
        persist()
    }

    func deleteCheckIn(_ checkIn: CheckIn) {
        data.checkIns.removeAll { $0.id == checkIn.id }
        persist()
    }

    /// Exactly the stored records, as readable JSON.
    func exportJSON() -> String {
        (try? String(decoding: AppCoding.encoder().encode(data), as: UTF8.self)) ?? "{}"
    }

    /// Removes everything and returns the app to its first-launch state.
    func eraseAll() {
        do {
            try persistence.erase()
            lastError = nil
        } catch {
            lastError = "Stored data could not be removed."
        }
        data = .empty
    }

    private func persist() {
        do {
            try persistence.save(data)
            lastError = nil
        } catch {
            lastError = "Your change could not be saved on this device."
        }
    }
}

import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData
import SwiftUI

/// iCloud sync: the journal's store mirrored to the user's private CloudKit database while it's on.
///
/// Entries and their photos sync; visited places (`PlaceTracker`'s samples) and the app's settings
/// stay on the device. The store is one file either way: turning sync on uploads what's already in it,
/// turning it off stops mirroring and leaves both copies as they are.
@Observable
final class ICloudSync {
    static let shared = ICloudSync()

    nonisolated static let enabledKey = "iCloudSyncEnabled"
    nonisolated static let containerID = "iCloud.com.maxsun.journal"

    nonisolated static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// The journal's store, mirrored to iCloud or not. Replaced when sync is switched, so every view's
    /// queries move to the new one at once.
    private(set) var container: ModelContainer

    /// Whether the store is mirroring now (the setting can be on with mirroring failed to start).
    private(set) var isSyncing: Bool

    /// When the last upload or download finished, this run.
    private(set) var lastSynced: Date?
    /// Why the last attempt failed, cleared by the next one that works.
    private(set) var lastError: String?
    /// Whether iCloud can be used at all: signed in, and not restricted.
    private(set) var accountAvailable = true
    /// When a download from iCloud last finished, this run.
    private(set) var lastImportEnded: Date?

    private init() {
        let syncing = Self.isEnabled
        let (container, mirrored) = Self.makeContainer(syncing: syncing)
        self.container = container
        self.isSyncing = mirrored
        observeEvents()
    }

    /// Turns sync on or off: the setting now; the store at the next safe moment (`applySetting`).
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        Task { await refreshAccountStatus() }
    }

    /// While the store is being swapped: the tabs (and every `@Query` in them) are taken out first,
    /// so no query is alive while its store changes — one updated in place, even on its way out,
    /// made SwiftUI abort.
    private(set) var isSwapping = false

    /// Brings the store in line with the setting: one that mirrors, or doesn't. Called where nothing
    /// is being edited (the onboarding finishing, Settings closing): the tabs go, the store changes,
    /// the tabs come back on it. Unsaved changes are saved first.
    func applySetting() {
        let enabled = Self.isEnabled
        guard enabled != isSyncing, !isSwapping else { return }
        try? container.mainContext.save()
        // Entries open in a stack belong to the old store's context.
        AppRouter.shared.journalPath.removeAll()
        AppRouter.shared.openEntries.removeAll()
        withoutAnimation { isSwapping = true }
        Task { @MainActor in
            // Once the tabs are gone.
            try? await Task.sleep(for: .milliseconds(50))
            let (container, mirrored) = Self.makeContainer(syncing: enabled)
            withoutAnimation {
                self.container = container
                isSyncing = mirrored
                lastError = nil
            }
            try? await Task.sleep(for: .milliseconds(50))
            withoutAnimation { isSwapping = false }
        }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// How many entries the journal already has in iCloud (trashed ones too), read straight from
    /// CloudKit: the zone SwiftData mirrors into, with each record's type and nothing else (no text,
    /// no photos). 0 when there's no journal there yet; nil when it can't be told (no account, no
    /// network).
    nonisolated static func remoteEntryCount() async -> Int? {
        #if DEBUG
        // `-fakeICloudEntries N` (a launch argument, so read as a string).
        if UserDefaults.standard.object(forKey: "fakeICloudEntries") != nil {
            return UserDefaults.standard.integer(forKey: "fakeICloudEntries")
        }
        #endif
        let container = CKContainer(identifier: containerID)
        guard (try? await container.accountStatus()) == .available else { return nil }
        let database = container.privateCloudDatabase
        // Where Core Data's CloudKit mirroring keeps a store's records; entries are `CD_Entry`.
        let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await database.recordZone(for: zone)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return 0
        } catch {
            return nil
        }
        var count = 0
        var token: CKServerChangeToken?
        var moreComing = true
        do {
            while moreComing {
                let changes = try await database.recordZoneChanges(inZoneWith: zone, since: token, desiredKeys: [], resultsLimit: nil)
                for result in changes.modificationResultsByID.values {
                    if case .success(let modification) = result, modification.record.recordType == "CD_Entry" {
                        count += 1
                    }
                }
                token = changes.changeToken
                moreComing = changes.moreComing
            }
        } catch {
            return nil
        }
        return count
    }

    /// How many entries are in the store on this device now, trashed ones too (to compare with
    /// `remoteEntryCount`).
    func localEntryCount() -> Int {
        (try? container.mainContext.fetchCount(FetchDescriptor<Entry>())) ?? 0
    }

    func refreshAccountStatus() async {
        let status = try? await CKContainer(identifier: Self.containerID).accountStatus()
        accountAvailable = status == .available
    }

    private static func makeContainer(syncing: Bool) -> (ModelContainer, Bool) {
        let schema = Schema([Entry.self, Attachment.self])
        // Named explicitly as "default", the store SwiftData has always used, so switching never
        // starts an empty one.
        if syncing {
            let configuration = ModelConfiguration("default", schema: schema, cloudKitDatabase: .private(containerID))
            if let container = try? ModelContainer(for: schema, configurations: configuration) {
                return (container, true)
            }
        }
        let configuration = ModelConfiguration("default", schema: schema, cloudKitDatabase: .none)
        do {
            return (try ModelContainer(for: schema, configurations: configuration), false)
        } catch {
            fatalError("The journal's store couldn't be opened: \(error)")
        }
    }

    /// SwiftData mirrors through Core Data's CloudKit container, which reports each import and export.
    private func observeEvents() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event, event.endDate != nil
            else { return }
            let succeeded = event.succeeded
            let message = event.error?.localizedDescription
            let type = event.type
            MainActor.assumeIsolated {
                guard let self else { return }
                if succeeded {
                    if type != .setup { self.lastSynced = .now }
                    if type == .import { self.lastImportEnded = .now }
                    self.lastError = nil
                } else {
                    self.lastError = message
                }
            }
        }
    }
}

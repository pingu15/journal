import CoreLocation
import EventKit
import Observation
import Photos

/// What the app may read, observed: the day sheet rebuilds every day it has loaded when any of it
/// changes, so access granted on one day (or in Settings) shows on the days beside it too.
/// `PhotoLibrary` and `CalendarEvents` keep their statuses here as they change; location is
/// `LocationService`'s own.
@Observable
final class AccessStatus {
    static let shared = AccessStatus()

    var photos = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var calendar = EKEventStore.authorizationStatus(for: .event)

    private init() {}
}

/// Everything a day's sections show depends on, compared to tell when to rebuild them.
struct DayAccess: Hashable {
    let photos: PHAuthorizationStatus
    let calendar: EKAuthorizationStatus
    let location: CLAuthorizationStatus
    let tracking: Bool

    /// Read where it's observed (a view's body), so the view updates with it.
    static func current(tracking: Bool) -> DayAccess {
        DayAccess(
            photos: AccessStatus.shared.photos,
            calendar: AccessStatus.shared.calendar,
            location: LocationService.shared.authorizationStatus,
            tracking: tracking
        )
    }
}

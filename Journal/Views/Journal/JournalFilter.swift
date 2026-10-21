import Foundation

enum JournalFilter: Hashable, CaseIterable {
    case all
    case recentlyDeleted

    var label: String {
        switch self {
        case .all: "All Entries"
        case .recentlyDeleted: "Recently Deleted"
        }
    }

    var symbol: String {
        switch self {
        case .all: "book.closed"
        case .recentlyDeleted: "trash"
        }
    }
}

import MapKit
import SwiftData
import SwiftUI

/// A place on the map: one entry with a location.
struct EntryPin: Equatable {
    let id: PersistentIdentifier
    let coordinate: CLLocationCoordinate2D

    static func == (a: EntryPin, b: EntryPin) -> Bool {
        a.id == b.id && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }
}

/// The entries' places as sand dots on an `MKMapView`, which groups nearby dots into one with a
/// count (SwiftUI's `Map` can't cluster). Tapping a dot opens its entry; tapping a group zooms in on
/// it, or — when its entries are all in the same spot, so zooming can't split it — opens them as a
/// list. Long-pressing the map asks for a new entry there.
struct EntryMap: UIViewRepresentable {
    let pins: [EntryPin]
    let onOpen: ([PersistentIdentifier]) -> Void
    let onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.register(EntryDotView.self, forAnnotationViewWithReuseIdentifier: EntryDotView.reuseID)
        map.register(EntryClusterView.self, forAnnotationViewWithReuseIdentifier: EntryClusterView.reuseID)

        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        press.minimumPressDuration = 0.5
        map.addGestureRecognizer(press)

        context.coordinator.update(map, with: pins)
        Self.fit(map.annotations, in: map, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(map, with: pins)
    }

    /// Shows all of `annotations`, clear of the screen's edges and the floating tab bar.
    static func fit(_ annotations: [MKAnnotation], in map: MKMapView, animated: Bool) {
        guard !annotations.isEmpty else { return }
        let rect = annotations.reduce(MKMapRect.null) { rect, annotation in
            let point = MKMapPoint(annotation.coordinate)
            return rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        // A single spot still shows its neighbourhood.
        let minimum = MKMapRect(origin: rect.origin, size: MKMapSize(width: 4000, height: 4000))
        let shown = rect.size.width < minimum.size.width && rect.size.height < minimum.size.height
            ? minimum.offsetBy(dx: -2000 + rect.size.width / 2, dy: -2000 + rect.size.height / 2)
            : rect
        map.setVisibleMapRect(shown, edgePadding: UIEdgeInsets(top: 60, left: 50, bottom: 140, right: 50), animated: animated)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: EntryMap
        private var shown: [PersistentIdentifier: EntryAnnotation] = [:]

        init(parent: EntryMap) {
            self.parent = parent
        }

        /// Adds, moves and removes annotations to match `pins`, leaving unchanged ones alone.
        func update(_ map: MKMapView, with pins: [EntryPin]) {
            let wanted = Dictionary(pins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let gone = shown.filter { id, annotation in
                guard let pin = wanted[id] else { return true }
                return pin != annotation.pin
            }
            map.removeAnnotations(Array(gone.values))
            gone.keys.forEach { shown[$0] = nil }

            let added = pins.filter { shown[$0.id] == nil }.map(EntryAnnotation.init)
            added.forEach { shown[$0.pin.id] = $0 }
            map.addAnnotations(added)
        }

        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            parent.onLongPress(coordinate)
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MKClusterAnnotation:
                map.dequeueReusableAnnotationView(withIdentifier: EntryClusterView.reuseID, for: annotation)
            case is EntryAnnotation:
                map.dequeueReusableAnnotationView(withIdentifier: EntryDotView.reuseID, for: annotation)
            default:
                nil
            }
        }

        func mapView(_ map: MKMapView, didSelect annotation: MKAnnotation) {
            map.deselectAnnotation(annotation, animated: false)
            if let entry = annotation as? EntryAnnotation {
                parent.onOpen([entry.pin.id])
            } else if let cluster = annotation as? MKClusterAnnotation {
                let members = cluster.memberAnnotations.compactMap { $0 as? EntryAnnotation }
                if Self.spread(of: members) < 50 {
                    parent.onOpen(members.map(\.pin.id))
                } else {
                    EntryMap.fit(members, in: map, animated: true)
                }
            }
        }

        /// How far apart (in meters) the farthest two of `annotations` are, roughly.
        private static func spread(of annotations: [EntryAnnotation]) -> CLLocationDistance {
            guard let first = annotations.first else { return 0 }
            let origin = CLLocation(latitude: first.coordinate.latitude, longitude: first.coordinate.longitude)
            return annotations.map {
                origin.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
            }.max() ?? 0
        }
    }
}

private final class EntryAnnotation: NSObject, MKAnnotation {
    let pin: EntryPin
    var coordinate: CLLocationCoordinate2D { pin.coordinate }

    init(_ pin: EntryPin) {
        self.pin = pin
    }
}

/// One entry: a small sand dot ringed in white.
private final class EntryDotView: MKAnnotationView {
    static let reuseID = "entry"
    private static let size: CGFloat = 16

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "entries"
        collisionMode = .circle
        frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        backgroundColor = UITheme.accent
        layer.cornerRadius = Self.size / 2
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        clusteringIdentifier = "entries"
    }
}

/// Several entries close together: a bigger sand dot with their count.
private final class EntryClusterView: MKAnnotationView {
    static let reuseID = "cluster"
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        backgroundColor = UITheme.accent
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        let count = (annotation as? MKClusterAnnotation)?.memberAnnotations.count ?? 0
        label.text = count.formatted()
        // A little bigger for bigger groups.
        let side: CGFloat = count < 10 ? 30 : count < 100 ? 36 : 42
        frame = CGRect(x: 0, y: 0, width: side, height: side)
        layer.cornerRadius = side / 2
        label.frame = bounds
        accessibilityLabel = "\(count) entries"
    }
}

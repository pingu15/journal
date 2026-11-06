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

/// The entries' places as numbered sand dots on an `MKMapView`, which groups nearby entries into one
/// dot (SwiftUI's `Map` can't cluster). Tapping a dot opens its entry, or lists a group's. Long-pressing the map asks for a new entry there. It opens on the current location, or
/// fitted to every dot without one.
struct EntryMap: UIViewRepresentable {
    let pins: [EntryPin]
    /// Goes back to the current location whenever this changes.
    let recenterCount: Int
    let onOpen: ([PersistentIdentifier]) -> Void
    let onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        // The location dot takes the map's tint, which would otherwise be the app's.
        map.tintColor = UITheme.userLocation
        map.register(EntryDotView.self, forAnnotationViewWithReuseIdentifier: EntryDotView.reuseID)

        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        press.minimumPressDuration = 0.5
        map.addGestureRecognizer(press)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)

        context.coordinator.update(map, with: pins)
        Self.fit(map.annotations, in: map)
        context.coordinator.showCurrentLocation(in: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(map, with: pins)
        if recenterCount != context.coordinator.recenterCount {
            context.coordinator.recenterCount = recenterCount
            context.coordinator.showCurrentLocation(in: map, animated: true)
        }
    }

    /// Shows all of `annotations`, clear of the screen's edges and the floating tab bar.
    static func fit(_ annotations: [MKAnnotation], in map: MKMapView) {
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
        map.setVisibleMapRect(shown, edgePadding: UIEdgeInsets(top: 60, left: 50, bottom: 140, right: 50), animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: EntryMap
        var recenterCount: Int
        private var shown: [PersistentIdentifier: EntryAnnotation] = [:]

        init(parent: EntryMap) {
            self.parent = parent
            recenterCount = parent.recenterCount
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

        /// Goes to the last known location at once if there is one (the app refreshes it on launch),
        /// and to the fresh one (asking for access the first time) only if that's somewhere else.
        func showCurrentLocation(in map: MKMapView, animated: Bool = false) {
            let known = LocationService.shared.lastKnownLocation
            if let known {
                map.showsUserLocation = true
                map.setRegion(Self.region(around: known), animated: animated)
            }
            Task { [weak map] in
                guard let location = try? await LocationService.shared.currentLocation(), let map else { return }
                map.showsUserLocation = true
                if let known, location.distance(from: known) < 500 { return }
                map.setRegion(Self.region(around: location), animated: true)
            }
        }

        /// The neighbourhood around `location`.
        private static func region(around location: CLLocation) -> MKCoordinateRegion {
            MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000)
        }

        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            parent.onLongPress(coordinate)
        }

        /// Taps on dots are caught here, not through MapKit's selection, which holds a tap for half a
        /// second to rule out a double tap. The dot is found by where the dots are, not by hit-testing:
        /// the location dot is drawn above them and took the tap when it was close by.
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let hit = Self.dots(in: map)
                .map { dot in (dot, dot.convert(dot.bounds, to: map)) }
                .filter { $0.1.contains(point) }
                // Overlapping dots: the one whose center is nearest.
                .min { Self.distance($0.1, point) < Self.distance($1.1, point) }?.0
            if let dot = hit, let annotation = dot.annotation {
                dot.pulse()
                open(annotation)
            }
        }

        /// The dots on screen (not those folded into a group).
        private static func dots(in view: UIView) -> [EntryDotView] {
            view.subviews.flatMap { subview -> [EntryDotView] in
                if let dot = subview as? EntryDotView {
                    return dot.isHidden || dot.alpha < 0.01 ? [] : [dot]
                }
                return dots(in: subview)
            }
        }

        private static func distance(_ frame: CGRect, _ point: CGPoint) -> CGFloat {
            hypot(frame.midX - point.x, frame.midY - point.y)
        }

        /// The map's own gestures carry on alongside the tap.
        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MKClusterAnnotation, is EntryAnnotation:
                let view = map.dequeueReusableAnnotationView(withIdentifier: EntryDotView.reuseID, for: annotation)
                (view as? EntryDotView)?.onActivate = { [weak self] in self?.open(annotation) }
                return view
            default:
                return nil
            }
        }

        /// The location dot does nothing either: it sits under the dots, and it would take their taps.
        func mapView(_ map: MKMapView, didAdd views: [MKAnnotationView]) {
            views.first { $0.annotation is MKUserLocation }?.isEnabled = false
        }

        private func open(_ annotation: MKAnnotation) {
            if let entry = annotation as? EntryAnnotation {
                parent.onOpen([entry.pin.id])
            } else if let cluster = annotation as? MKClusterAnnotation {
                parent.onOpen(cluster.memberAnnotations.compactMap { ($0 as? EntryAnnotation)?.pin.id })
            }
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

/// An entry, or several close together: a sand dot ringed in white with their count, always the
/// same size.
private final class EntryDotView: MKAnnotationView {
    static let reuseID = "entry"
    private static let size: CGFloat = 36
    private let label = UILabel()
    /// VoiceOver's activation, as MapKit's selection is off.
    var onActivate: (() -> Void)?

    // Set with the annotation: MapKit decides what to group as soon as it has the view, and views
    // are reused between entries and groups.
    override var annotation: MKAnnotation? {
        didSet { updateClustering() }
    }

    private func updateClustering() {
        clusteringIdentifier = annotation is MKClusterAnnotation ? nil : "entries"
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        updateClustering()
        // Tapped through `Coordinator.tap(_:)`.
        isEnabled = false
        collisionMode = .circle
        frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        backgroundColor = UITheme.accent
        layer.cornerRadius = Self.size / 2
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.frame = bounds.insetBy(dx: 4, dy: 4)
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        // The dot doesn't grow, so a long count or a large text size shrinks to fit.
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Dips and springs back, as a pressed button would: its taps don't come through the view itself
    /// (`isEnabled` is off), so this stands in for a pressed state.
    func pulse() {
        UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        } completion: { _ in
            UIView.animate(springDuration: 0.3, bounce: 0.3) {
                self.transform = .identity
            }
        }
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        let count = (annotation as? MKClusterAnnotation)?.memberAnnotations.count ?? 1
        label.text = count.formatted()
        accessibilityLabel = count == 1 ? "1 entry" : "\(count) entries"
    }
}

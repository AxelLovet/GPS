import SwiftUI
import MapKit
import VeloCore

/// Carte affichant un ou plusieurs circuits, la trace parcourue et la position.
///
/// MapKit est utilisé **uniquement pour l'affichage** : il ne sait pas calculer
/// d'itinéraire cyclable (voir `docs/ROUTING_ENGINE.md`). Les tracés proviennent
/// du moteur de routage et sont convertis ici en `MapPolyline`.
struct RouteMapView: View {
    /// Circuit mis en avant.
    var route: CyclingRoute?
    /// Circuits affichés en retrait, sélectionnables.
    var alternates: [CyclingRoute] = []
    /// Trace réellement parcourue pendant la sortie.
    var track: [GeographicCoordinate] = []
    /// Position courante, dessinée avec un cap lorsqu'il est connu.
    var currentPosition: GeographicCoordinate?
    var currentCourse: Double?
    /// Départ imposé manuellement.
    var customStart: GeographicCoordinate?
    /// Affiche la position bleue du système.
    var showsUserLocation = true

    @Binding var cameraPosition: MapCameraPosition
    /// Appelé lorsque l'utilisateur touche la carte pour désigner un départ.
    var onTapCoordinate: ((GeographicCoordinate) -> Void)?
    var onSelectAlternate: ((CyclingRoute) -> Void)?

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: .all) {
                if showsUserLocation {
                    UserAnnotation()
                }

                // Les alternatives sont dessinées en premier pour rester sous
                // le circuit sélectionné.
                ForEach(alternates) { alternate in
                    MapPolyline(coordinates: alternate.coordinates.map(\.clCoordinate))
                        .stroke(
                            Color.veloRouteAlternate.opacity(0.55),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                }

                if let route {
                    // Double trait : un liseré sombre sous la ligne colorée, ce
                    // qui garde le tracé lisible sur un fond de carte clair en
                    // plein soleil.
                    MapPolyline(coordinates: route.coordinates.map(\.clCoordinate))
                        .stroke(
                            Color.black.opacity(0.35),
                            style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)
                        )
                    MapPolyline(coordinates: route.coordinates.map(\.clCoordinate))
                        .stroke(
                            Color.veloRoute,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                        )

                    ForEach(directionMarkers(for: route), id: \.self) { marker in
                        Annotation("", coordinate: marker.coordinate.clCoordinate) {
                            DirectionChevron(bearing: marker.bearing)
                        }
                        .annotationTitles(.hidden)
                    }

                    if let start = route.start {
                        Marker(Strings.Map.start, systemImage: "flag.fill", coordinate: start.clCoordinate)
                            .tint(Color.veloStart)
                    }
                    if let end = route.end, route.loopClosureDistance > 60 {
                        Marker(
                            Strings.Map.finish,
                            systemImage: "flag.checkered",
                            coordinate: end.clCoordinate
                        )
                        .tint(Color.veloFinish)
                    }
                }

                if track.count > 1 {
                    MapPolyline(coordinates: track.map(\.clCoordinate))
                        .stroke(
                            Color.veloTrack,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                }

                if let customStart {
                    Marker(
                        Strings.Map.chosenStart,
                        systemImage: "mappin",
                        coordinate: customStart.clCoordinate
                    )
                    .tint(Color.veloStart)
                }

                if let currentPosition, !showsUserLocation {
                    Annotation("", coordinate: currentPosition.clCoordinate) {
                        RiderMarker(course: currentCourse)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .onTapGesture(coordinateSpace: .local) { screenPoint in
                guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                handleTap(
                    at: GeographicCoordinate(coordinate),
                    screenPoint: screenPoint,
                    proxy: proxy
                )
            }
        }
    }

    /// Interprète un appui sur la carte.
    ///
    /// Deux usages se partagent le même geste : désigner un point de départ, et
    /// sélectionner un circuit alternatif en touchant son tracé. Le premier est
    /// prioritaire, car il n'est actif que lorsque l'utilisateur l'a demandé.
    private func handleTap(
        at coordinate: GeographicCoordinate,
        screenPoint: CGPoint,
        proxy: MapProxy
    ) {
        if let onTapCoordinate {
            onTapCoordinate(coordinate)
            return
        }
        guard let onSelectAlternate, !alternates.isEmpty else { return }

        // La proximité est mesurée **à l'écran**, pas en mètres.
        //
        // C'est à la fois plus juste et plus simple : une tolérance en points
        // reste constante quel que soit le zoom, alors qu'une tolérance en
        // mètres devrait être recalculée à partir de l'échelle affichée — que
        // `MapProxy` n'expose pas avant iOS 18.
        //
        // 24 points correspondent grossièrement au rayon d'un doigt sur un
        // trait dessiné en 5 points de large.
        let tolerance: CGFloat = 24
        var closest: (route: CyclingRoute, distance: CGFloat)?

        for alternate in alternates {
            let distance = minimumScreenDistance(
                from: screenPoint,
                to: alternate.coordinates,
                proxy: proxy
            )
            if closest == nil || distance < closest!.distance {
                closest = (alternate, distance)
            }
        }

        if let closest, closest.distance <= tolerance {
            onSelectAlternate(closest.route)
        }
    }

    /// Distance à l'écran, en points, entre un appui et le tracé le plus proche.
    private func minimumScreenDistance(
        from point: CGPoint,
        to polyline: [GeographicCoordinate],
        proxy: MapProxy
    ) -> CGFloat {
        guard !polyline.isEmpty else { return .infinity }

        // Les tracés comptent jusqu'à quelques milliers de points ; on
        // n'en échantillonne qu'une partie. À 25 m d'intervalle, un point sur
        // quatre reste très en deçà de la tolérance d'un doigt.
        let step = max(polyline.count / 400, 1)
        var best = CGFloat.infinity

        for index in stride(from: 0, to: polyline.count, by: step) {
            guard let projected = proxy.convert(polyline[index].clCoordinate, to: .local) else {
                continue
            }
            best = min(best, hypot(projected.x - point.x, projected.y - point.y))
        }
        return best
    }

    /// Chevrons indiquant le sens de parcours.
    ///
    /// Sur une boucle, savoir dans quel sens on part est essentiel : le même
    /// tracé parcouru à l'envers ne donne ni les mêmes montées ni les mêmes
    /// intersections.
    private func directionMarkers(for route: CyclingRoute) -> [DirectionMarker] {
        let coordinates = route.coordinates
        guard coordinates.count > 8 else { return [] }

        let cumulative = route.cumulativeDistances
        guard let total = cumulative.last, total > 0 else { return [] }

        // Un chevron tous les huitièmes de parcours : assez pour lever
        // l'ambiguïté, pas assez pour surcharger la carte.
        let count = 8
        var markers: [DirectionMarker] = []
        for step in 0..<count {
            let target = total * (Double(step) + 0.5) / Double(count)
            guard let index = cumulative.firstIndex(where: { $0 >= target }),
                  index + 1 < coordinates.count else { continue }
            markers.append(
                DirectionMarker(
                    coordinate: coordinates[index],
                    bearing: Geodesy.bearing(from: coordinates[index], to: coordinates[index + 1])
                )
            )
        }
        return markers
    }
}

struct DirectionMarker: Hashable {
    let coordinate: GeographicCoordinate
    let bearing: Double
}

/// Petit chevron orienté dans le sens du parcours.
private struct DirectionChevron: View {
    let bearing: Double

    var body: some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .shadow(radius: 1)
            .rotationEffect(.degrees(bearing))
            .accessibilityHidden(true)
    }
}

/// Position du cycliste avec son cap.
private struct RiderMarker: View {
    let course: Double?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(.white, lineWidth: 3))
            if let course, course >= 0 {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: -14)
                    .rotationEffect(.degrees(course))
            }
        }
        .shadow(radius: 2)
        .accessibilityLabel(Strings.Map.currentPosition)
    }
}

// MARK: - Cadrage

extension MapCameraPosition {
    /// Cadre l'ensemble d'un tracé avec une marge.
    static func fitting(coordinates: [GeographicCoordinate], padding: Double = 1.35) -> MapCameraPosition {
        guard let region = MKCoordinateRegion.enclosing(coordinates, padding: padding) else {
            return .automatic
        }
        return .region(region)
    }

    /// Vue rapprochée orientée dans le sens de marche, pour la navigation.
    static func navigating(
        at coordinate: GeographicCoordinate,
        heading: Double,
        distance: Double = 420
    ) -> MapCameraPosition {
        .camera(
            MapCamera(
                centerCoordinate: coordinate.clCoordinate,
                distance: distance,
                heading: heading,
                // Une légère inclinaison donne de la profondeur et laisse voir
                // plus loin devant, comme sur un GPS de voiture.
                pitch: 55
            )
        )
    }

    /// Vue rapprochée nord en haut.
    static func northUp(at coordinate: GeographicCoordinate, distance: Double = 600) -> MapCameraPosition {
        .camera(
            MapCamera(centerCoordinate: coordinate.clCoordinate, distance: distance, heading: 0, pitch: 0)
        )
    }
}

extension MKCoordinateRegion {
    /// Plus petite région contenant toutes les coordonnées, élargie d'une marge.
    static func enclosing(
        _ coordinates: [GeographicCoordinate],
        padding: Double = 1.35
    ) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }

        var minLatitude = coordinates[0].latitude
        var maxLatitude = coordinates[0].latitude
        var minLongitude = coordinates[0].longitude
        var maxLongitude = coordinates[0].longitude

        for coordinate in coordinates {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        // Un plancher évite une région dégénérée quand tous les points sont
        // presque confondus, ce qui produirait un zoom absurde.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * padding, 0.004),
            longitudeDelta: max((maxLongitude - minLongitude) * padding, 0.004)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

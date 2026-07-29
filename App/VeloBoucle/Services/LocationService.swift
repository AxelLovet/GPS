import Foundation
import CoreLocation
import Observation
import VeloCore

/// État de l'autorisation de localisation, exprimé en termes utiles à l'interface.
enum LocationAuthorizationState: Equatable {
    case notDetermined
    case denied
    case restricted
    case whenInUse
    case always

    var isUsable: Bool { self == .whenInUse || self == .always }

    /// Vrai si le suivi peut se poursuivre écran verrouillé.
    var supportsBackgroundTracking: Bool { self == .always }
}

/// Précision demandée au GPS, ajustée selon ce que fait l'utilisateur.
///
/// C'est le principal levier d'autonomie de l'application. Demander en
/// permanence la meilleure précision possible viderait la batterie d'un iPhone
/// en trois à quatre heures ; une sortie à vélo peut durer plus longtemps.
enum LocationAccuracyMode {
    /// L'utilisateur consulte la carte : une position à 100 m suffit à centrer
    /// la vue, et le GPS peut rester largement au repos.
    case browsing
    /// Navigation ou enregistrement en cours : précision maximale, mises à jour
    /// continues, y compris en arrière-plan.
    case navigating

    var desiredAccuracy: CLLocationAccuracy {
        switch self {
        case .browsing: return kCLLocationAccuracyHundredMeters
        case .navigating: return kCLLocationAccuracyBestForNavigation
        }
    }

    /// Distance minimale entre deux notifications, en mètres.
    ///
    /// À vélo, un point toutes les 5 m à 25 km/h correspond à environ 1,4 relevé
    /// par seconde : assez dense pour un tracé fidèle, sans réveiller
    /// l'application inutilement à l'arrêt.
    var distanceFilter: CLLocationDistance {
        switch self {
        case .browsing: return 50
        case .navigating: return 5
        }
    }
}

/// Accès à la localisation, exposé sous forme observable.
///
/// Toutes les positions sont converties en `LocationSample` — un type de
/// `VeloCore` sans dépendance à CoreLocation — avant d'être transmises au reste
/// de l'application. Le cœur métier reste ainsi testable sans simulateur.
@Observable
@MainActor
final class LocationService: NSObject {
    private let manager: CLLocationManager

    private(set) var authorization: LocationAuthorizationState = .notDetermined
    /// Vrai lorsque l'utilisateur a désactivé la position exacte.
    private(set) var hasReducedAccuracy = false
    private(set) var latestSample: LocationSample?
    private(set) var latestError: VeloError?
    private(set) var accuracyMode: LocationAccuracyMode = .browsing
    private(set) var isUpdating = false

    /// Cap magnétique de l'appareil, pour orienter la carte à l'arrêt.
    private(set) var heading: Double?

    /// Flux des relevés destinés à la navigation et à l'enregistrement.
    ///
    /// Un `AsyncStream` plutôt qu'un delegate permet aux vues-modèles de
    /// consommer les positions avec `for await`, et garantit qu'elles cessent de
    /// les recevoir dès que leur tâche est annulée.
    private var continuations: [UUID: AsyncStream<LocationSample>.Continuation] = [:]

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = accuracyMode.desiredAccuracy
        manager.distanceFilter = accuracyMode.distanceFilter
        manager.activityType = .fitness
        // Le système ne doit jamais interrompre le suivi de sa propre initiative
        // pendant une sortie : une pause au sommet d'un col ressemble beaucoup à
        // un arrêt définitif du point de vue de CoreLocation.
        manager.pausesLocationUpdatesAutomatically = false
        refreshAuthorization()

        // Sous test d'interface, le simulateur ne fournit pas toujours de
        // position ; on en injecte une pour que les scénarios soient
        // reproductibles. Sans l'argument de lancement dédié, ce chemin est
        // inatteignable.
        if let sample = UITestingSupport.simulatedSample {
            latestSample = sample
        }
    }

    // MARK: - Autorisations

    /// Demande l'autorisation « pendant l'utilisation ».
    ///
    /// iOS impose de commencer par ce niveau ; « toujours » ne peut être demandé
    /// qu'ensuite, et seulement une fois. L'application ne le réclame donc qu'au
    /// démarrage d'une sortie, moment où la raison en est évidente pour
    /// l'utilisateur.
    func requestWhenInUseAuthorization() {
        guard authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Demande l'autorisation « toujours », nécessaire au suivi écran verrouillé.
    func requestAlwaysAuthorization() {
        guard authorization == .whenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    /// Demande temporairement la position exacte pour une navigation.
    func requestTemporaryFullAccuracy() async {
        guard hasReducedAccuracy else { return }
        do {
            try await manager.requestTemporaryFullAccuracyAuthorization(
                withPurposeKey: "NavigationAccuracy"
            )
            hasReducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
        } catch {
            AppLog.location.notice("Précision exacte refusée pour cette session")
        }
    }

    private func refreshAuthorization() {
        authorization = Self.state(for: manager.authorizationStatus)
        hasReducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy

        switch authorization {
        case .denied: latestError = .locationPermissionDenied
        case .restricted: latestError = .locationPermissionRestricted
        default: if latestError?.isPermissionRelated == true { latestError = nil }
        }
    }

    private static func state(for status: CLAuthorizationStatus) -> LocationAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedWhenInUse: return .whenInUse
        case .authorizedAlways: return .always
        @unknown default: return .notDetermined
        }
    }

    // MARK: - Suivi

    /// Passe dans un mode de précision donné et démarre le suivi.
    func startUpdating(mode: LocationAccuracyMode) {
        guard authorization.isUsable else {
            requestWhenInUseAuthorization()
            return
        }

        accuracyMode = mode
        manager.desiredAccuracy = mode.desiredAccuracy
        manager.distanceFilter = mode.distanceFilter

        // Le suivi en arrière-plan n'est activé que pour une navigation réelle,
        // et seulement si l'utilisateur a accordé « Toujours ». L'activer sans
        // ces deux conditions provoquerait une exception à l'exécution.
        let wantsBackground = (mode == .navigating) && authorization.supportsBackgroundTracking
        manager.allowsBackgroundLocationUpdates = wantsBackground
        manager.showsBackgroundLocationIndicator = wantsBackground

        manager.startUpdatingLocation()
        if mode == .navigating, CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        isUpdating = true
    }

    /// Arrête toute mise à jour. À appeler dès qu'aucun écran n'a besoin de la
    /// position, pour ne pas consommer de batterie inutilement.
    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        isUpdating = false
    }

    /// Demande une position unique, sans lancer de suivi continu.
    func requestOneShotLocation() {
        guard authorization.isUsable else {
            requestWhenInUseAuthorization()
            return
        }
        manager.requestLocation()
    }

    /// Flux de relevés. Le flux se termine lorsque l'appelant l'abandonne.
    func sampleStream() -> AsyncStream<LocationSample> {
        let identifier = UUID()
        let (stream, continuation) = AsyncStream<LocationSample>.makeStream()
        continuations[identifier] = continuation

        // Le désabonnement est indispensable : sans lui, chaque écran ouvert
        // laisserait une continuation morte à alimenter à chaque relevé GPS.
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.continuations.removeValue(forKey: identifier)
            }
        }
        return stream
    }

    private func broadcast(_ sample: LocationSample) {
        latestSample = sample
        for continuation in continuations.values {
            continuation.yield(sample)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in refreshAuthorization() }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let samples = locations.map(LocationSample.init(location:))
        Task { @MainActor in
            latestError = nil
            for sample in samples where sample.coordinate.isValid {
                broadcast(sample)
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        // Un cap dont la précision est négative signale une boussole non
        // calibrée : mieux vaut ne rien afficher que d'orienter la carte à
        // l'envers.
        guard newHeading.headingAccuracy >= 0 else { return }
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in heading = value }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let mapped: VeloError
        if let clError = error as? CLError {
            switch clError.code {
            case .denied: mapped = .locationPermissionDenied
            case .locationUnknown: mapped = .locationUnavailable
            default: mapped = .locationUnavailable
            }
        } else {
            mapped = .locationUnavailable
        }
        // Le message d'erreur est journalisé sans aucune coordonnée.
        AppLog.location.notice("Échec de localisation : \(mapped.title, privacy: .public)")
        Task { @MainActor in latestError = mapped }
    }
}

// MARK: - Conversions

extension LocationSample {
    /// Convertit une position CoreLocation en relevé indépendant du framework.
    init(location: CLLocation) {
        self.init(
            coordinate: GeographicCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.verticalAccuracy >= 0 ? location.altitude : nil
            ),
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            speed: location.speed,
            course: location.course
        )
    }
}

extension GeographicCoordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

private extension VeloError {
    var isPermissionRelated: Bool {
        self == .locationPermissionDenied || self == .locationPermissionRestricted
    }
}

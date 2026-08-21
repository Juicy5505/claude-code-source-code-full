import CoreLocation
import Foundation
import MapKit

struct GolfCourseSearchRequest: Equatable, Sendable {
    static let query = "golf course"

    let centerLatitude: Double
    let centerLongitude: Double
    let radiusMeters: Double
    let naturalLanguageQuery: String
}

struct GolfCourseSearchPlace: Equatable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
}

protocol GolfCourseSearchProviding: Sendable {
    func search(_ request: GolfCourseSearchRequest) async throws -> [GolfCourseSearchPlace]
}

/// Key-free facility discovery backed by Apple's on-device MapKit integration.
struct AppleMapsGolfCourseSearchProvider: GolfCourseSearchProviding {
    private final class SearchBox: @unchecked Sendable {
        let search: MKLocalSearch

        init(_ search: MKLocalSearch) {
            self.search = search
        }
    }

    func search(_ request: GolfCourseSearchRequest) async throws -> [GolfCourseSearchPlace] {
        try Task.checkCancellation()

        let mapRequest = MKLocalSearch.Request()
        mapRequest.naturalLanguageQuery = request.naturalLanguageQuery
        mapRequest.resultTypes = .pointOfInterest
        mapRequest.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: request.centerLatitude,
                longitude: request.centerLongitude
            ),
            latitudinalMeters: request.radiusMeters * 2,
            longitudinalMeters: request.radiusMeters * 2
        )
        if #available(iOS 18.0, *) {
            mapRequest.pointOfInterestFilter = MKPointOfInterestFilter(including: [.golf])
        }

        let box = SearchBox(MKLocalSearch(request: mapRequest))
        let response = try await withTaskCancellationHandler {
            try await box.search.start()
        } onCancel: {
            box.search.cancel()
        }
        try Task.checkCancellation()

        // MapKit normally returns a small set. The hard cap prevents an
        // unexpectedly large response from entering ranking or UI state.
        return response.mapItems.prefix(100).compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            return GolfCourseSearchPlace(
                name: name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }
}

enum GolfCourseMatchConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

enum GolfCourseSelectionState: String, Codable, Equatable, Sendable {
    case suggested
    case userConfirmed
}

/// A nearby golf facility returned by Apple Maps place search.
///
/// This model identifies a facility only. It does not include, infer, or claim
/// licensed tee, green, fairway, boundary, or per-hole geometry.
struct GolfCourseCandidate: Codable, Equatable, Hashable, Identifiable, Sendable {
    static let appleMapsSource = "Apple Maps place search"

    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let confidence: GolfCourseMatchConfidence
    let source: String
    let selectionState: GolfCourseSelectionState

    func userConfirmed() -> GolfCourseCandidate {
        GolfCourseCandidate(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            distanceMeters: distanceMeters,
            confidence: confidence,
            source: source,
            selectionState: .userConfirmed
        )
    }
}

enum GolfCourseSuggestion: Equatable, Sendable {
    /// One credible facility match. It remains a suggestion until the golfer
    /// explicitly confirms it.
    case suggested(GolfCourseCandidate)
    /// Multiple plausible facilities are too close to distinguish safely.
    case ambiguous([GolfCourseCandidate])
    /// Search returned no valid facility within the configured distance.
    case noneNearby
}

actor GolfCourseLocator {
    struct Configuration: Equatable, Sendable {
        let searchRadiusMeters: Double
        let maximumSuggestionDistanceMeters: Double
        let ambiguityDistanceDeltaMeters: Double
        let ambiguityDistanceRatio: Double
        let highConfidenceDistanceMeters: Double
        let mediumConfidenceDistanceMeters: Double
        let maximumDisplayedCandidates: Int

        init(
            searchRadiusMeters: Double = 15_000,
            maximumSuggestionDistanceMeters: Double = 8_000,
            ambiguityDistanceDeltaMeters: Double = 750,
            ambiguityDistanceRatio: Double = 1.5,
            highConfidenceDistanceMeters: Double = 1_500,
            mediumConfidenceDistanceMeters: Double = 3_500,
            maximumDisplayedCandidates: Int = 3
        ) {
            let boundedSearchRadius = min(max(searchRadiusMeters, 500), 50_000)
            self.searchRadiusMeters = boundedSearchRadius
            self.maximumSuggestionDistanceMeters = min(
                max(maximumSuggestionDistanceMeters, 100),
                boundedSearchRadius
            )
            self.ambiguityDistanceDeltaMeters = min(
                max(ambiguityDistanceDeltaMeters, 0),
                boundedSearchRadius
            )
            self.ambiguityDistanceRatio = max(1, ambiguityDistanceRatio)
            self.highConfidenceDistanceMeters = max(0, highConfidenceDistanceMeters)
            self.mediumConfidenceDistanceMeters = max(
                self.highConfidenceDistanceMeters,
                mediumConfidenceDistanceMeters
            )
            self.maximumDisplayedCandidates = min(max(maximumDisplayedCandidates, 2), 10)
        }
    }

    enum LocatorError: LocalizedError, Equatable {
        case invalidOrigin
        case staleRequest

        var errorDescription: String? {
            switch self {
            case .invalidOrigin:
                "A valid iPhone GPS fix is required to suggest a nearby course."
            case .staleRequest:
                "A newer nearby-course search replaced this request."
            }
        }
    }

    private let provider: any GolfCourseSearchProviding
    private let configuration: Configuration
    private var generation = 0
    private var activeSearch: Task<[GolfCourseSearchPlace], Error>?

    init(
        provider: any GolfCourseSearchProviding = AppleMapsGolfCourseSearchProvider(),
        configuration: Configuration = Configuration()
    ) {
        self.provider = provider
        self.configuration = configuration
    }

    /// Suggests a facility near the supplied current GPS fix. Starting a new
    /// request cancels the prior search, and late results are rejected.
    func suggestCourse(near fix: LocationFix) async throws -> GolfCourseSuggestion {
        guard Self.isValidOrigin(fix) else { throw LocatorError.invalidOrigin }

        activeSearch?.cancel()
        generation += 1
        let requestGeneration = generation
        let request = GolfCourseSearchRequest(
            centerLatitude: fix.latitude,
            centerLongitude: fix.longitude,
            radiusMeters: configuration.searchRadiusMeters,
            naturalLanguageQuery: GolfCourseSearchRequest.query
        )
        let provider = provider
        let task = Task {
            try await provider.search(request)
        }
        activeSearch = task

        do {
            let places = try await task.value
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw LocatorError.staleRequest }
            activeSearch = nil
            return Self.rank(
                places: places,
                near: fix,
                configuration: configuration
            )
        } catch is CancellationError {
            if generation == requestGeneration {
                activeSearch = nil
            }
            throw CancellationError()
        } catch {
            if generation == requestGeneration {
                activeSearch = nil
            }
            throw error
        }
    }

    func cancelSearch() {
        generation += 1
        activeSearch?.cancel()
        activeSearch = nil
    }

    nonisolated static func rank(
        places: [GolfCourseSearchPlace],
        near fix: LocationFix,
        configuration: Configuration = Configuration()
    ) -> GolfCourseSuggestion {
        guard isValidOrigin(fix) else { return .noneNearby }

        var seenIDs: Set<String> = []
        let ranked = places.prefix(100).compactMap { place -> GolfCourseCandidate? in
            guard let name = validName(place.name),
                  isValidCoordinate(latitude: place.latitude, longitude: place.longitude)
            else { return nil }

            let distance = distanceMeters(
                fromLatitude: fix.latitude,
                longitude: fix.longitude,
                toLatitude: place.latitude,
                longitude: place.longitude
            )
            guard distance.isFinite,
                  distance <= configuration.maximumSuggestionDistanceMeters
            else { return nil }

            let id = stableID(name: name, latitude: place.latitude, longitude: place.longitude)
            guard seenIDs.insert(id).inserted else { return nil }
            let confidence: GolfCourseMatchConfidence
            if distance <= configuration.highConfidenceDistanceMeters {
                confidence = .high
            } else if distance <= configuration.mediumConfidenceDistanceMeters {
                confidence = .medium
            } else {
                confidence = .low
            }
            return GolfCourseCandidate(
                id: id,
                name: name,
                latitude: place.latitude,
                longitude: place.longitude,
                distanceMeters: distance,
                confidence: confidence,
                source: GolfCourseCandidate.appleMapsSource,
                selectionState: .suggested
            )
        }.sorted {
            if abs($0.distanceMeters - $1.distanceMeters) > 0.001 {
                return $0.distanceMeters < $1.distanceMeters
            }
            return $0.id < $1.id
        }

        guard let first = ranked.first else { return .noneNearby }
        if ranked.count > 1 {
            let second = ranked[1]
            let distanceDelta = second.distanceMeters - first.distanceMeters
            let ratio = second.distanceMeters / max(first.distanceMeters, 1)
            if distanceDelta <= configuration.ambiguityDistanceDeltaMeters ||
                ratio <= configuration.ambiguityDistanceRatio {
                return .ambiguous(Array(ranked.prefix(configuration.maximumDisplayedCandidates)))
            }
        }
        return .suggested(first)
    }

    private nonisolated static func isValidOrigin(_ fix: LocationFix) -> Bool {
        isValidCoordinate(latitude: fix.latitude, longitude: fix.longitude) &&
            fix.horizontalAccuracyMeters.isFinite &&
            fix.horizontalAccuracyMeters >= 0 &&
            fix.horizontalAccuracyMeters <= 100
    }

    private nonisolated static func isValidCoordinate(
        latitude: Double,
        longitude: Double
    ) -> Bool {
        latitude.isFinite && longitude.isFinite &&
            (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    private nonisolated static func validName(_ rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 160,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return name
    }

    private nonisolated static func stableID(
        name: String,
        latitude: Double,
        longitude: Double
    ) -> String {
        let normalizedName = name
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")
        let latitudeMicrodegrees = Int64((latitude * 1_000_000).rounded())
        let longitudeMicrodegrees = Int64((longitude * 1_000_000).rounded())
        return "\(normalizedName)|\(latitudeMicrodegrees)|\(longitudeMicrodegrees)"
    }

    private nonisolated static func distanceMeters(
        fromLatitude: Double,
        longitude fromLongitude: Double,
        toLatitude: Double,
        longitude toLongitude: Double
    ) -> Double {
        let earthRadiusMeters = 6_371_008.8
        let latitude1 = fromLatitude * .pi / 180
        let latitude2 = toLatitude * .pi / 180
        let latitudeDelta = (toLatitude - fromLatitude) * .pi / 180
        let longitudeDelta = (toLongitude - fromLongitude) * .pi / 180
        let haversine = pow(sin(latitudeDelta / 2), 2) +
            cos(latitude1) * cos(latitude2) * pow(sin(longitudeDelta / 2), 2)
        let centralAngle = 2 * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))
        return earthRadiusMeters * centralAngle
    }
}

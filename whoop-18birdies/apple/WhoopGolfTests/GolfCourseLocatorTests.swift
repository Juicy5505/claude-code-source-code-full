import XCTest
@testable import WhoopGolf

final class GolfCourseLocatorTests: XCTestCase {
    func testRankingReturnsNearestUnconfirmedAppleMapsFacility() {
        let origin = makeOrigin()
        let places = [
            GolfCourseSearchPlace(
                name: "Far Fairways",
                latitude: origin.latitude + 0.05,
                longitude: origin.longitude
            ),
            GolfCourseSearchPlace(
                name: "  Peachtree Golf Club  ",
                latitude: origin.latitude + 0.002,
                longitude: origin.longitude
            )
        ]

        let result = GolfCourseLocator.rank(places: places, near: origin)
        guard case .suggested(let candidate) = result else {
            return XCTFail("Expected one clear facility suggestion")
        }

        XCTAssertEqual(candidate.name, "Peachtree Golf Club")
        XCTAssertEqual(candidate.confidence, .high)
        XCTAssertEqual(candidate.source, "Apple Maps place search")
        XCTAssertEqual(candidate.selectionState, .suggested)
        XCTAssertLessThan(candidate.distanceMeters, 300)

        let repeated = GolfCourseLocator.rank(places: Array(places.reversed()), near: origin)
        guard case .suggested(let repeatedCandidate) = repeated else {
            return XCTFail("Expected stable repeated suggestion")
        }
        XCTAssertEqual(repeatedCandidate.id, candidate.id)
    }

    func testNearbyFacilitiesRemainAmbiguousUntilUserConfirmsOne() {
        let origin = makeOrigin()
        let places = [
            GolfCourseSearchPlace(
                name: "North Course",
                latitude: origin.latitude + 0.002,
                longitude: origin.longitude
            ),
            GolfCourseSearchPlace(
                name: "South Course",
                latitude: origin.latitude + 0.0035,
                longitude: origin.longitude
            )
        ]

        let result = GolfCourseLocator.rank(places: places, near: origin)
        guard case .ambiguous(let candidates) = result else {
            return XCTFail("Nearby facilities must require a user choice")
        }

        XCTAssertEqual(candidates.map(\.name), ["North Course", "South Course"])
        XCTAssertTrue(candidates.allSatisfy { $0.selectionState == .suggested })
        let confirmed = candidates[1].userConfirmed()
        XCTAssertEqual(confirmed.id, candidates[1].id)
        XCTAssertEqual(confirmed.selectionState, .userConfirmed)
        XCTAssertEqual(candidates[1].selectionState, .suggested)
    }

    func testRankingRejectsInvalidDuplicateAndTooDistantResponses() {
        let origin = makeOrigin()
        let invalidOrFar = [
            GolfCourseSearchPlace(name: "", latitude: origin.latitude, longitude: origin.longitude),
            GolfCourseSearchPlace(name: "Bad latitude", latitude: 91, longitude: origin.longitude),
            GolfCourseSearchPlace(name: "Bad longitude", latitude: origin.latitude, longitude: .infinity),
            GolfCourseSearchPlace(
                name: "Too Far Golf Club",
                latitude: origin.latitude + 0.1,
                longitude: origin.longitude
            )
        ]
        XCTAssertEqual(
            GolfCourseLocator.rank(places: invalidOrFar, near: origin),
            .noneNearby
        )

        let repeated = GolfCourseSearchPlace(
            name: "Same Course",
            latitude: origin.latitude + 0.002,
            longitude: origin.longitude
        )
        let deduplicated = GolfCourseLocator.rank(
            places: [repeated, repeated],
            near: origin
        )
        guard case .suggested(let candidate) = deduplicated else {
            return XCTFail("Duplicate map records should produce one suggestion")
        }
        XCTAssertEqual(candidate.name, "Same Course")
    }

    func testStableTieBreakDoesNotDependOnProviderOrdering() {
        let origin = makeOrigin()
        let alpha = GolfCourseSearchPlace(
            name: "Alpha Club",
            latitude: origin.latitude + 0.002,
            longitude: origin.longitude
        )
        let beta = GolfCourseSearchPlace(
            name: "Beta Club",
            latitude: origin.latitude + 0.002,
            longitude: origin.longitude
        )

        let firstOrder = GolfCourseLocator.rank(places: [beta, alpha], near: origin)
        let secondOrder = GolfCourseLocator.rank(places: [alpha, beta], near: origin)
        guard case .ambiguous(let firstCandidates) = firstOrder,
              case .ambiguous(let secondCandidates) = secondOrder
        else { return XCTFail("Equal-distance facilities should remain ambiguous") }

        XCTAssertEqual(firstCandidates.map(\.id), secondCandidates.map(\.id))
        XCTAssertEqual(firstCandidates.map(\.name), ["Alpha Club", "Beta Club"])
    }

    func testInjectedProviderReceivesBoundedNaturalLanguageRequest() async throws {
        let origin = makeOrigin()
        let provider = RecordingCourseSearchProvider(
            places: [
                GolfCourseSearchPlace(
                    name: "Test Links",
                    latitude: origin.latitude + 0.002,
                    longitude: origin.longitude
                )
            ]
        )
        let locator = GolfCourseLocator(
            provider: provider,
            configuration: .init(searchRadiusMeters: 500_000)
        )

        let result = try await locator.suggestCourse(near: origin)
        guard case .suggested = result else {
            return XCTFail("Expected injected result to be ranked")
        }
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].naturalLanguageQuery, "golf course")
        XCTAssertEqual(requests[0].centerLatitude, origin.latitude)
        XCTAssertEqual(requests[0].centerLongitude, origin.longitude)
        XCTAssertEqual(requests[0].radiusMeters, 50_000)
    }

    func testNewSearchCancelsOlderProviderRequest() async throws {
        let origin = makeOrigin()
        let provider = CancellableCourseSearchProvider(
            result: GolfCourseSearchPlace(
                name: "Latest Course",
                latitude: origin.latitude + 0.002,
                longitude: origin.longitude
            )
        )
        let locator = GolfCourseLocator(provider: provider)

        let oldRequest = Task {
            try await locator.suggestCourse(near: origin)
        }
        for _ in 0..<100 {
            if await provider.numberOfCalls() > 0 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        guard await provider.numberOfCalls() == 1 else {
            oldRequest.cancel()
            return XCTFail("The first injected search did not start")
        }

        let latest = try await locator.suggestCourse(near: origin)
        guard case .suggested(let candidate) = latest else {
            return XCTFail("Expected latest request to complete")
        }
        XCTAssertEqual(candidate.name, "Latest Course")

        do {
            _ = try await oldRequest.value
            XCTFail("Expected replaced request to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected cancellation, received \(error)")
        }
    }

    private func makeOrigin() -> LocationFix {
        let observedAt = Date(timeIntervalSince1970: 1_780_000_000)
        return LocationFix(
            latitude: 33.749,
            longitude: -84.388,
            altitudeMeters: 300,
            horizontalAccuracyMeters: 5,
            capturedAt: observedAt,
            provenance: DataProvenance(
                source: .iphoneGPS,
                observedAt: observedAt,
                quality: .verified
            )
        )
    }
}

private actor RecordingCourseSearchProvider: GolfCourseSearchProviding {
    private let places: [GolfCourseSearchPlace]
    private var requests: [GolfCourseSearchRequest] = []

    init(places: [GolfCourseSearchPlace]) {
        self.places = places
    }

    func search(_ request: GolfCourseSearchRequest) async throws -> [GolfCourseSearchPlace] {
        requests.append(request)
        return places
    }

    func recordedRequests() -> [GolfCourseSearchRequest] {
        requests
    }
}

private actor CancellableCourseSearchProvider: GolfCourseSearchProviding {
    private let result: GolfCourseSearchPlace
    private var callCount = 0

    init(result: GolfCourseSearchPlace) {
        self.result = result
    }

    func search(_ request: GolfCourseSearchRequest) async throws -> [GolfCourseSearchPlace] {
        callCount += 1
        if callCount == 1 {
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        return [result]
    }

    func numberOfCalls() -> Int {
        callCount
    }
}

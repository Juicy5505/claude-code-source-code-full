import Foundation
import XCTest
@testable import WhoopGolf

final class EighteenBirdiesCompanionLinkTests: XCTestCase {
    func testPrimaryDestinationIsTheApprovedGenericHTTPSAppLink() {
        let url = EighteenBirdiesCompanionLink.primaryURL

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "18birdies.app.link")
        XCTAssertEqual(url.path, "/xL2YVQHu4T")
        XCTAssertNil(url.query)
        XCTAssertNil(url.user)
        XCTAssertNil(url.password)
    }

    func testFallbackDestinationIsTheOfficialAppStoreListing() {
        let url = EighteenBirdiesCompanionLink.appStoreURL

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "apps.apple.com")
        XCTAssertEqual(url.path, "/app/id892700751")
        XCTAssertNil(url.query)
    }

    func testAcceptedPrimaryHandoffDoesNotOpenFallback() {
        XCTAssertNil(
            EighteenBirdiesCompanionLink.fallbackURL(afterPrimaryAccepted: true)
        )
    }

    func testRejectedPrimaryHandoffUsesAppStoreFallback() {
        XCTAssertEqual(
            EighteenBirdiesCompanionLink.fallbackURL(afterPrimaryAccepted: false),
            EighteenBirdiesCompanionLink.appStoreURL
        )
    }
}

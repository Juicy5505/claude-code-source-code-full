import CoreLocation
import Foundation

/// Detects the watch reporting your phone's position instead of your own.
///
/// THE PROBLEM
///
/// On an Apple Watch Series 5 — and every model before the Series 8 — watchOS
/// uses the PAIRED IPHONE'S GPS whenever the phone is in Bluetooth range,
/// because the watch's battery is far smaller. Apple only changed this for the
/// Ultra, Series 8 and SE (2nd generation), which use their own receiver even
/// with a phone nearby.
///
/// For most uses that is a sensible trade. For golf with the phone in the cart
/// it is fatal: you walk thirty yards to your ball and swing, but the fix comes
/// from the cart, so every shot is measured cart-to-cart. The yardages look
/// plausible — they are just measurements of where your cart went. Nothing
/// errors, nothing warns, and the round is quietly worthless.
///
/// WHY IT HAS TO BE INFERRED
///
/// There is no API to force the watch's own receiver, and `CLLocation` carries
/// no field naming the radio that produced it. So this infers it from a
/// disagreement between two sensors that cannot both be wrong in the same
/// direction: the accelerometer says the wrist has been walking, and the
/// position says it has not moved.
///
/// A wrist that has been swinging like a walk for a full minute has covered
/// something like 80 metres. If the reported position moved less than
/// `staleRadiusM` in that time, the position is not describing the wrist.
///
/// FALSE POSITIVES ARE DESIGNED OUT, NOT TUNED OUT
///
/// The window is long (60 s), the walking threshold is a clear majority of
/// samples, and the displacement bound is generous. Standing over a ball,
/// waiting on a tee, or a slow GPS lock all fail at least one condition. The
/// cost of a false positive is one dismissible warning; the cost of a false
/// negative is a round of fabricated yardages, so the asymmetry is deliberate.
@MainActor
final class GPSSourceCheck {
    /// How long the wrist must be walking before the comparison means anything.
    static let windowSeconds: TimeInterval = 60

    /// Below this fraction of moving samples, the wearer was not really walking.
    static let walkingThreshold = 0.55

    /// Walking for a minute covers ~80 m. Anything under this is not the wrist.
    static let staleRadiusM: CLLocationDistance = 25

    private var anchor: CLLocation?
    private var anchoredAt: Date?

    /// Set once a mismatch is seen. Sticky: the phone does not usually leave
    /// the cart mid-round, so clearing it would just make the warning flicker.
    private(set) var warning: String?

    /// Feed the newest fix and the wrist's recent walking evidence.
    ///
    /// Returns a warning the first time a mismatch is confirmed, and nil
    /// otherwise, so the caller can surface it once rather than every second.
    func update(location: CLLocation?, walkingFraction: Double, now: Date = Date()) -> String? {
        guard warning == nil else { return nil }
        guard let location, location.horizontalAccuracy >= 0 else { return nil }

        guard let anchor, let anchoredAt else {
            self.anchor = location
            self.anchoredAt = now
            return nil
        }

        let elapsed = now.timeIntervalSince(anchoredAt)
        guard elapsed >= Self.windowSeconds else { return nil }

        let moved = location.distance(from: anchor)

        // Re-anchor either way: the next window should judge the next minute,
        // not accumulate against a position from ten minutes ago.
        self.anchor = location
        self.anchoredAt = now

        guard walkingFraction >= Self.walkingThreshold else { return nil }
        guard moved < Self.staleRadiusM else { return nil }

        warning = "GPS looks like your PHONE — put it in Airplane Mode"
        return warning
    }

    /// The full explanation, for the round summary rather than the tiny live
    /// status line.
    static let explanation = """
        Your watch was walking but its position barely moved, which means the \
        fix is coming from your iPhone rather than your wrist. A Series 5 uses \
        the phone's GPS whenever the phone is in range. With the phone in your \
        cart, every shot gets measured cart-to-cart.

        Fix: put the phone in Airplane Mode, or leave it out of Bluetooth range.
        """

    func reset() {
        anchor = nil
        anchoredAt = nil
        warning = nil
    }
}

package stgael.ballistics;

/** Physical properties used by the independent Gael projectile simulator. */
public record BallisticProfile(
        double muzzleVelocityMetresPerSecond,
        double gravityMetresPerSecondSquared,
        double dragPerSecond,
        double maximumDistanceMetres,
        double maximumFlightSeconds) {

    public BallisticProfile {
        requirePositive(muzzleVelocityMetresPerSecond, "muzzle velocity");
        requireNonNegative(gravityMetresPerSecondSquared, "gravity");
        requireNonNegative(dragPerSecond, "drag");
        requirePositive(maximumDistanceMetres, "maximum distance");
        requirePositive(maximumFlightSeconds, "maximum flight time");
    }

    private static void requirePositive(double value, String name) {
        if (!Double.isFinite(value) || value <= 0.0) {
            throw new IllegalArgumentException(name + " must be finite and positive");
        }
    }

    private static void requireNonNegative(double value, String name) {
        if (!Double.isFinite(value) || value < 0.0) {
            throw new IllegalArgumentException(name + " must be finite and non-negative");
        }
    }
}

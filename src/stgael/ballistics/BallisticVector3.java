package stgael.ballistics;

/** Small immutable vector in world metres, independent of Project Zomboid classes. */
public record BallisticVector3(double x, double y, double z) {
    public static final BallisticVector3 ZERO = new BallisticVector3(0.0, 0.0, 0.0);

    public BallisticVector3 {
        if (!Double.isFinite(x) || !Double.isFinite(y) || !Double.isFinite(z)) {
            throw new IllegalArgumentException("Ballistic vectors must be finite");
        }
    }

    public BallisticVector3 add(BallisticVector3 other) {
        return new BallisticVector3(x + other.x, y + other.y, z + other.z);
    }

    public BallisticVector3 subtract(BallisticVector3 other) {
        return new BallisticVector3(x - other.x, y - other.y, z - other.z);
    }

    public BallisticVector3 scale(double amount) {
        if (!Double.isFinite(amount)) throw new IllegalArgumentException("Scale must be finite");
        return new BallisticVector3(x * amount, y * amount, z * amount);
    }

    public double dot(BallisticVector3 other) {
        return x * other.x + y * other.y + z * other.z;
    }

    public double lengthSquared() { return dot(this); }
    public double length() { return Math.hypot(Math.hypot(x, y), z); }

    public BallisticVector3 normalized() {
        double magnitude = length();
        if (!Double.isFinite(magnitude) || magnitude < 1.0e-12) {
            throw new IllegalStateException("Cannot normalize a zero or non-finite vector");
        }
        return scale(1.0 / magnitude);
    }
}

package stgael.ballistics;

import java.util.Objects;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

/** Mutable flight state. All positions and velocities use metres and seconds. */
public final class BallisticProjectile {
    private static final AtomicLong NEXT_ID = new AtomicLong(1L);

    private final long id;
    private final BallisticProfile profile;
    private final Object owner;
    private final Object shotData;
    private final ArrayList<BallisticVector3> trail = new ArrayList<>();
    private BallisticVector3 position;
    private BallisticVector3 velocity;
    private double travelledMetres;
    private double flightSeconds;
    private boolean finished;

    private BallisticProjectile(long id, BallisticProfile profile,
                                BallisticVector3 position, BallisticVector3 velocity,
                                Object owner, Object shotData) {
        this.id = id;
        this.profile = Objects.requireNonNull(profile, "profile");
        this.position = Objects.requireNonNull(position, "position");
        this.velocity = Objects.requireNonNull(velocity, "velocity");
        this.owner = owner;
        this.shotData = shotData;
        this.trail.add(position);
    }

    public static BallisticProjectile launch(BallisticProfile profile,
                                              BallisticVector3 muzzlePosition,
                                              BallisticVector3 barrelDirection) {
        return launch(profile, muzzlePosition, barrelDirection, null);
    }

    public static BallisticProjectile launch(BallisticProfile profile,
                                              BallisticVector3 muzzlePosition,
                                              BallisticVector3 barrelDirection,
                                              Object owner) {
        return launch(profile, muzzlePosition, barrelDirection, owner, null);
    }

    public static BallisticProjectile launch(BallisticProfile profile,
                                              BallisticVector3 muzzlePosition,
                                              BallisticVector3 barrelDirection,
                                              Object owner, Object shotData) {
        Objects.requireNonNull(profile, "profile");
        BallisticVector3 unitDirection = Objects.requireNonNull(barrelDirection, "barrelDirection").normalized();
        return new BallisticProjectile(NEXT_ID.getAndIncrement(), profile, muzzlePosition,
                unitDirection.scale(profile.muzzleVelocityMetresPerSecond()), owner, shotData);
    }

    /**
     * Advances one bounded simulation step with midpoint integration. Linear drag
     * opposes current velocity and gravity acts along negative world Z.
     */
    public BallisticSegment advance(double seconds) {
        if (finished) return new BallisticSegment(position, position, flightSeconds, flightSeconds);
        if (!Double.isFinite(seconds) || seconds <= 0.0 || seconds > 0.1) {
            throw new IllegalArgumentException("Step must be in (0, 0.1] seconds");
        }

        BallisticVector3 start = position;
        double startSeconds = flightSeconds;
        BallisticVector3 acceleration0 = acceleration(velocity);
        BallisticVector3 midpointVelocity = velocity.add(acceleration0.scale(seconds * 0.5));
        BallisticVector3 midpointAcceleration = acceleration(midpointVelocity);
        BallisticVector3 nextVelocity = velocity.add(midpointAcceleration.scale(seconds));
        BallisticVector3 nextPosition = position.add(midpointVelocity.scale(seconds));

        travelledMetres += nextPosition.subtract(position).length();
        flightSeconds += seconds;
        position = nextPosition;
        velocity = nextVelocity;
        trail.add(nextPosition);
        if (trail.size() > 48) trail.remove(0);
        finished = travelledMetres >= profile.maximumDistanceMetres()
                || flightSeconds >= profile.maximumFlightSeconds()
                || velocity.lengthSquared() < 1.0;
        return new BallisticSegment(start, nextPosition, startSeconds, flightSeconds);
    }

    /** Truncates the most recent step at a collision point and ends the shot. */
    public void stopAt(BallisticVector3 collisionPosition) {
        Objects.requireNonNull(collisionPosition, "collisionPosition");
        double overshoot = position.subtract(collisionPosition).length();
        travelledMetres = Math.max(0.0, travelledMetres - overshoot);
        position = collisionPosition;
        if (trail.isEmpty()) trail.add(collisionPosition);
        else trail.set(trail.size() - 1, collisionPosition);
        finished = true;
    }

    private BallisticVector3 acceleration(BallisticVector3 currentVelocity) {
        return new BallisticVector3(
                -currentVelocity.x() * profile.dragPerSecond(),
                -currentVelocity.y() * profile.dragPerSecond(),
                -profile.gravityMetresPerSecondSquared()
                        - currentVelocity.z() * profile.dragPerSecond());
    }

    public long id() { return id; }
    public BallisticProfile profile() { return profile; }
    public Object owner() { return owner; }
    /** Shot-specific weapon/ammo data retained until this projectile impacts. */
    public Object shotData() { return shotData; }
    public BallisticVector3 position() { return position; }
    public BallisticVector3 velocity() { return velocity; }
    /** Recent muzzle-to-flight samples, capped to keep diagnostic memory bounded. */
    public List<BallisticVector3> trailSnapshot() { return List.copyOf(trail); }
    public double travelledMetres() { return travelledMetres; }
    public double flightSeconds() { return flightSeconds; }
    public boolean finished() { return finished; }
}

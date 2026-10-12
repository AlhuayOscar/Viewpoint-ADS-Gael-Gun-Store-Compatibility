package stgael.ballistics;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.Objects;

/** Main-thread projectile owner with fixed-size collision sweeps and bounded work. */
public final class BallisticEngine {
    private static final double MAX_STEP_SECONDS = 0.02;
    private static final int MAX_STEPS_PER_FRAME = 25;
    private static final int MAX_ACTIVE_PROJECTILES = 512;

    private final ArrayList<BallisticProjectile> active = new ArrayList<>();

    public boolean launch(BallisticProfile profile, BallisticVector3 muzzle,
                          BallisticVector3 barrelDirection) {
        return launch(profile, muzzle, barrelDirection, null);
    }

    public boolean launch(BallisticProfile profile, BallisticVector3 muzzle,
                          BallisticVector3 barrelDirection, Object owner) {
        return launch(profile, muzzle, barrelDirection, owner, null);
    }

    public boolean launch(BallisticProfile profile, BallisticVector3 muzzle,
                          BallisticVector3 barrelDirection, Object owner, Object shotData) {
        if (active.size() >= MAX_ACTIVE_PROJECTILES) return false;
        active.add(BallisticProjectile.launch(profile, muzzle, barrelDirection, owner, shotData));
        return true;
    }

    /** Advances all shots and returns impacts in flight order for damage/effects adapters. */
    public List<Impact> update(double frameSeconds, BallisticCollisionResolver collisions) {
        Objects.requireNonNull(collisions, "collisions");
        if (!Double.isFinite(frameSeconds) || frameSeconds <= 0.0) return List.of();

        double boundedFrame = Math.min(frameSeconds, MAX_STEP_SECONDS * MAX_STEPS_PER_FRAME);
        int steps = Math.max(1, Math.min(MAX_STEPS_PER_FRAME,
                (int) Math.ceil(boundedFrame / MAX_STEP_SECONDS)));
        double stepSeconds = boundedFrame / steps;
        ArrayList<Impact> impacts = new ArrayList<>();

        for (int step = 0; step < steps; step++) {
            Iterator<BallisticProjectile> iterator = active.iterator();
            while (iterator.hasNext()) {
                BallisticProjectile projectile = iterator.next();
                BallisticSegment segment = projectile.advance(stepSeconds);
                BallisticCollision collision = collisions.firstCollision(projectile, segment);
                if (collision != null) {
                    projectile.stopAt(collision.position());
                    impacts.add(new Impact(projectile, collision));
                    iterator.remove();
                } else if (projectile.finished()) {
                    iterator.remove();
                }
            }
        }
        return Collections.unmodifiableList(impacts);
    }

    public int activeCount() { return active.size(); }
    public List<BallisticProjectile> activeProjectilesSnapshot() { return List.copyOf(active); }
    public void clear() { active.clear(); }

    public record Impact(BallisticProjectile projectile, BallisticCollision collision) {}
}

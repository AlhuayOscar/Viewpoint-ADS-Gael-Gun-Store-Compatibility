package stgael.ballistics;

/** Adapter contract: return the nearest collision on the segment, or null when clear. */
@FunctionalInterface
public interface BallisticCollisionResolver {
    BallisticCollision firstCollision(BallisticProjectile projectile, BallisticSegment segment);
}

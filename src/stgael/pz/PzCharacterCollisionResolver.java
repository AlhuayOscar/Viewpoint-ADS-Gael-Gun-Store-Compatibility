package stgael.pz;

import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Objects;
import java.util.Set;

import stgael.ballistics.BallisticCollision;
import stgael.ballistics.BallisticCollisionResolver;
import stgael.ballistics.BallisticProjectile;
import stgael.ballistics.BallisticSegment;
import stgael.ballistics.BallisticVector3;
import zombie.characters.IsoGameCharacter;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoMovingObject;

/** Swept cylindrical hit checks against characters in nearby PZ grid squares. */
public final class PzCharacterCollisionResolver implements BallisticCollisionResolver {
    private static final double CHARACTER_BODY_HEIGHT_METRES = 1.65;
    private static final double MIN_RADIUS_METRES = 0.20;
    private static final double MAX_RADIUS_METRES = 0.48;
    private static final double SQUARE_SCAN_SPACING_METRES = 0.40;

    private final IsoCell cell;
    private final PzBallisticCoordinates coordinates;

    public PzCharacterCollisionResolver(IsoCell cell, PzBallisticCoordinates coordinates) {
        this.cell = Objects.requireNonNull(cell, "cell");
        this.coordinates = Objects.requireNonNull(coordinates, "coordinates");
    }

    @Override
    public BallisticCollision firstCollision(BallisticProjectile projectile, BallisticSegment segment) {
        Objects.requireNonNull(projectile, "projectile");
        Objects.requireNonNull(segment, "segment");
        BallisticVector3 start = segment.start();
        BallisticVector3 delta = segment.end().subtract(start);
        double length = delta.length();
        int samples = Math.max(1, (int) Math.ceil(length / SQUARE_SCAN_SPACING_METRES));
        Set<IsoMovingObject> visited = Collections.newSetFromMap(new IdentityHashMap<>());
        double nearestT = Double.POSITIVE_INFINITY;
        IsoGameCharacter nearestTarget = null;

        for (int sample = 0; sample <= samples; sample++) {
            double fraction = sample / (double) samples;
            BallisticVector3 point = start.add(delta.scale(fraction));
            int x = coordinates.tileX(point);
            int y = coordinates.tileY(point);
            int z = coordinates.level(point);
            // A projectile's vertical coordinate is continuous, while PZ stores
            // characters in the square for their current floor. Search adjacent
            // floors too: a trajectory can intersect the upper/lower part of a
            // character's body while its sampled point rounds into a neighboring
            // level. The cylinder test below still decides whether it truly hits.
            for (int dz = -1; dz <= 1; dz++) {
                for (int dx = -1; dx <= 1; dx++) {
                    for (int dy = -1; dy <= 1; dy++) {
                        IsoGridSquare square = cell.getGridSquare(x + dx, y + dy, z + dz);
                        if (square == null) continue;
                        for (IsoMovingObject moving : square.getMovingObjects()) {
                            if (!(moving instanceof IsoGameCharacter target)
                                    || target == projectile.owner() || target.isDead()
                                    || !target.isShootable() || !visited.add(moving)) continue;
                            double t = intersectBodyCylinder(start, delta, target);
                            if (t >= 0.0 && t < nearestT) {
                                nearestT = t;
                                nearestTarget = target;
                            }
                        }
                    }
                }
            }
        }

        if (nearestTarget == null) return null;
        BallisticVector3 impact = start.add(delta.scale(nearestT));
        return new BallisticCollision(BallisticCollision.Kind.CHARACTER, impact, nearestTarget);
    }

    private double intersectBodyCylinder(BallisticVector3 start, BallisticVector3 delta,
                                         IsoGameCharacter target) {
        double centerX = target.getX() * coordinates.metresPerTile();
        double centerY = target.getY() * coordinates.metresPerTile();
        double widthRadius = target.getWidth() * coordinates.metresPerTile() * 0.5;
        double radius = Math.max(MIN_RADIUS_METRES, Math.min(MAX_RADIUS_METRES, widthRadius));
        double ground = target.getZ() * coordinates.metresPerLevel();
        double lowZ = ground + 0.10 - radius;
        double highZ = ground + CHARACTER_BODY_HEIGHT_METRES + radius;

        double dx = delta.x();
        double dy = delta.y();
        double ox = start.x() - centerX;
        double oy = start.y() - centerY;
        double a = dx * dx + dy * dy;
        double b = 2.0 * (ox * dx + oy * dy);
        double c = ox * ox + oy * oy - radius * radius;
        double horizontalLow = 0.0;
        double horizontalHigh = 1.0;
        if (a < 1.0e-12) {
            if (c > 0.0) return -1.0;
        } else {
            double discriminant = b * b - 4.0 * a * c;
            if (discriminant < 0.0) return -1.0;
            double root = Math.sqrt(discriminant);
            horizontalLow = Math.max(0.0, (-b - root) / (2.0 * a));
            horizontalHigh = Math.min(1.0, (-b + root) / (2.0 * a));
            if (horizontalLow > horizontalHigh) return -1.0;
        }

        double dz = delta.z();
        if (Math.abs(dz) < 1.0e-12) {
            return start.z() >= lowZ && start.z() <= highZ ? horizontalLow : -1.0;
        }
        double verticalA = (lowZ - start.z()) / dz;
        double verticalB = (highZ - start.z()) / dz;
        double verticalLow = Math.max(0.0, Math.min(verticalA, verticalB));
        double verticalHigh = Math.min(1.0, Math.max(verticalA, verticalB));
        double firstContact = Math.max(horizontalLow, verticalLow);
        return firstContact <= Math.min(horizontalHigh, verticalHigh) ? firstContact : -1.0;
    }
}

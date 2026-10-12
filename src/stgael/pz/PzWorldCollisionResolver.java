package stgael.pz;

import java.util.Objects;

import stgael.ballistics.BallisticCollision;
import stgael.ballistics.BallisticCollisionResolver;
import stgael.ballistics.BallisticProjectile;
import stgael.ballistics.BallisticSegment;
import stgael.ballistics.BallisticVector3;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquareCollisionData;
import zombie.iso.LosUtil;
import zombie.iso.Vector3;

/** PZ world-cover query for swept projectile segments; character hits are resolved separately. */
public final class PzWorldCollisionResolver implements BallisticCollisionResolver {
    private final IsoCell cell;
    private final PzBallisticCoordinates coordinates;
    private final boolean ignoreDoors;

    public PzWorldCollisionResolver(IsoCell cell, PzBallisticCoordinates coordinates,
                                    boolean ignoreDoors) {
        this.cell = Objects.requireNonNull(cell, "cell");
        this.coordinates = Objects.requireNonNull(coordinates, "coordinates");
        this.ignoreDoors = ignoreDoors;
    }

    @Override
    public BallisticCollision firstCollision(BallisticProjectile projectile, BallisticSegment segment) {
        Objects.requireNonNull(projectile, "projectile");
        Objects.requireNonNull(segment, "segment");
        BallisticVector3 start = segment.start();
        BallisticVector3 end = segment.end();
        IsoGridSquareCollisionData data = LosUtil.getFirstBlockingIsoGridSquare(cell,
                coordinates.tileX(start), coordinates.tileY(start), coordinates.level(start),
                coordinates.tileX(end), coordinates.tileY(end), coordinates.level(end), ignoreDoors);
        if (data == null || data.testResults != LosUtil.TestResults.Blocked) return null;

        Vector3 point = data.hitPosition;
        BallisticVector3 position;
        if (point != null && Float.isFinite(point.x) && Float.isFinite(point.y)
                && Float.isFinite(point.z)) {
            position = coordinates.collisionToMetres(point);
        } else if (data.isoGridSquare != null) {
            position = firstSquareContact(start, end, data.isoGridSquare);
            if (position == null) return null;
        } else {
            return null;
        }
        return new BallisticCollision(BallisticCollision.Kind.WORLD, position, data.isoGridSquare);
    }

    /** Find segment entry into the blocking tile when PZ omitted hitPosition. */
    private BallisticVector3 firstSquareContact(BallisticVector3 start, BallisticVector3 end,
                                                 zombie.iso.IsoGridSquare square) {
        double scale = coordinates.metresPerTile();
        double verticalScale = coordinates.metresPerLevel();
        double[] origin = {start.x(), start.y(), start.z()};
        double[] delta = {end.x() - start.x(), end.y() - start.y(), end.z() - start.z()};
        double[] min = {square.getX() * scale, square.getY() * scale, square.getZ() * verticalScale};
        double[] max = {min[0] + scale, min[1] + scale, min[2] + verticalScale};
        double entry = 0.0;
        double exit = 1.0;
        for (int axis = 0; axis < 3; axis++) {
            if (Math.abs(delta[axis]) < 1.0e-12) {
                if (origin[axis] < min[axis] || origin[axis] > max[axis]) return null;
                continue;
            }
            double first = (min[axis] - origin[axis]) / delta[axis];
            double second = (max[axis] - origin[axis]) / delta[axis];
            entry = Math.max(entry, Math.min(first, second));
            exit = Math.min(exit, Math.max(first, second));
            if (entry > exit) return null;
        }
        if (entry < 0.0 || entry > 1.0) return null;
        return start.add(end.subtract(start).scale(entry));
    }
}

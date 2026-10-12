package stgael.pz;

import java.util.Objects;
import java.util.Set;

import org.joml.Vector3f;

import stgael.ballistics.BallisticCollision;
import stgael.ballistics.BallisticCollisionResolver;
import stgael.ballistics.BallisticProjectile;
import stgael.ballistics.BallisticSegment;
import stgael.ballistics.BallisticVector3;
import zombie.iso.IsoCell;
import zombie.vehicles.BaseVehicle;

/** Swept vehicle collision adapter using PZ's native vehicle segment intersection. */
public final class PzVehicleCollisionResolver implements BallisticCollisionResolver {
    private static final double BROAD_RADIUS_METRES = 7.0;
    private static final double VERTICAL_RADIUS_METRES = 4.0;

    private final IsoCell cell;
    private final PzBallisticCoordinates coordinates;
    private final Vector3f startPz = new Vector3f();
    private final Vector3f endPz = new Vector3f();
    private final Vector3f hitPz = new Vector3f();

    public PzVehicleCollisionResolver(IsoCell cell, PzBallisticCoordinates coordinates) {
        this.cell = Objects.requireNonNull(cell, "cell");
        this.coordinates = Objects.requireNonNull(coordinates, "coordinates");
    }

    @Override
    public BallisticCollision firstCollision(BallisticProjectile projectile, BallisticSegment segment) {
        Objects.requireNonNull(projectile, "projectile");
        Objects.requireNonNull(segment, "segment");
        Set<BaseVehicle> vehicles;
        try {
            vehicles = cell.getVehicles();
        } catch (RuntimeException unavailable) {
            return null;
        }
        if (vehicles == null || vehicles.isEmpty()) return null;

        BallisticVector3 start = segment.start();
        BallisticVector3 end = segment.end();
        double dx = end.x() - start.x();
        double dy = end.y() - start.y();
        double dz = end.z() - start.z();
        double lengthSquared = dx * dx + dy * dy + dz * dz;
        if (!Double.isFinite(lengthSquared) || lengthSquared < 1.0e-12) return null;
        double horizontalLengthSquared = dx * dx + dy * dy;
        double lowZ = Math.min(start.z(), end.z()) - VERTICAL_RADIUS_METRES;
        double highZ = Math.max(start.z(), end.z()) + VERTICAL_RADIUS_METRES;

        setPz(start, startPz);
        setPz(end, endPz);
        double nearestT = Double.POSITIVE_INFINITY;
        BaseVehicle nearestVehicle = null;
        BallisticVector3 nearestPoint = null;

        for (BaseVehicle vehicle : vehicles) {
            if (vehicle == null) continue;
            double vehicleX = vehicle.getX() * coordinates.metresPerTile();
            double vehicleY = vehicle.getY() * coordinates.metresPerTile();
            double vehicleZ = vehicle.getZ() * coordinates.metresPerLevel();
            if (vehicleZ < lowZ || vehicleZ > highZ) continue;
            if (distanceSquaredToHorizontalSegment(vehicleX, vehicleY, start,
                    dx, dy, horizontalLengthSquared) > BROAD_RADIUS_METRES * BROAD_RADIUS_METRES) continue;

            Vector3f intersection;
            try {
                intersection = vehicle.getIntersectPoint(startPz, endPz, hitPz);
            } catch (RuntimeException unavailable) {
                continue;
            }
            if (intersection == null || !Float.isFinite(intersection.x)
                    || !Float.isFinite(intersection.y) || !Float.isFinite(intersection.z)) continue;

            BallisticVector3 point = coordinates.collisionToMetres(
                    new zombie.iso.Vector3(intersection.x, intersection.y, intersection.z));
            double t = ((point.x() - start.x()) * dx + (point.y() - start.y()) * dy
                    + (point.z() - start.z()) * dz) / lengthSquared;
            if (t < 0.0 || t > 1.0 || t >= nearestT) continue;
            nearestT = t;
            nearestVehicle = vehicle;
            nearestPoint = point;
        }

        return nearestVehicle == null ? null
                : new BallisticCollision(BallisticCollision.Kind.VEHICLE, nearestPoint, nearestVehicle);
    }

    private double distanceSquaredToHorizontalSegment(double x, double y, BallisticVector3 start,
                                                      double dx, double dy, double lengthSquared) {
        double t = lengthSquared < 1.0e-12 ? 0.0
                : ((x - start.x()) * dx + (y - start.y()) * dy) / lengthSquared;
        t = Math.max(0.0, Math.min(1.0, t));
        double nearestX = start.x() + dx * t;
        double nearestY = start.y() + dy * t;
        double offsetX = x - nearestX;
        double offsetY = y - nearestY;
        return offsetX * offsetX + offsetY * offsetY;
    }

    private void setPz(BallisticVector3 point, Vector3f output) {
        output.set((float) (point.x() / coordinates.metresPerTile()),
                (float) (point.y() / coordinates.metresPerTile()),
                (float) (point.z() / coordinates.metresPerLevel()));
    }
}

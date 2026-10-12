package stgael.pz;

import java.util.Objects;

import stgael.ballistics.BallisticCollision;
import stgael.ballistics.BallisticCollisionResolver;
import stgael.ballistics.BallisticProjectile;
import stgael.ballistics.BallisticSegment;
import stgael.ballistics.BallisticVector3;
import zombie.iso.IsoCell;

/** Chooses the nearest character, vehicle, or solid-world contact along a swept segment. */
public final class PzCollisionResolver implements BallisticCollisionResolver {
    private final PzWorldCollisionResolver world;
    private final PzCharacterCollisionResolver characters;
    private final PzVehicleCollisionResolver vehicles;

    public PzCollisionResolver(IsoCell cell, PzBallisticCoordinates coordinates,
                               boolean ignoreDoors) {
        Objects.requireNonNull(cell, "cell");
        Objects.requireNonNull(coordinates, "coordinates");
        world = new PzWorldCollisionResolver(cell, coordinates, ignoreDoors);
        characters = new PzCharacterCollisionResolver(cell, coordinates);
        vehicles = new PzVehicleCollisionResolver(cell, coordinates);
    }

    @Override
    public BallisticCollision firstCollision(BallisticProjectile projectile, BallisticSegment segment) {
        BallisticCollision worldHit = world.firstCollision(projectile, segment);
        BallisticCollision characterHit = characters.firstCollision(projectile, segment);
        BallisticCollision vehicleHit = vehicles.firstCollision(projectile, segment);
        BallisticCollision nearest = nearer(worldHit, characterHit, segment.start());
        return nearer(nearest, vehicleHit, segment.start());
    }

    private static BallisticCollision nearer(BallisticCollision first, BallisticCollision second,
                                             BallisticVector3 start) {
        if (first == null) return second;
        if (second == null) return first;
        return second.position().subtract(start).lengthSquared()
                < first.position().subtract(start).lengthSquared() ? second : first;
    }
}

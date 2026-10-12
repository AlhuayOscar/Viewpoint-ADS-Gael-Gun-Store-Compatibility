package stgael.pz;

import java.util.List;
import java.util.Objects;

import stgael.ballistics.BallisticEngine;
import stgael.ballistics.BallisticProfile;
import stgael.ballistics.BallisticProjectile;
import stgael.ballistics.BallisticVector3;
import zombie.characters.IsoGameCharacter;
import zombie.inventory.types.HandWeapon;
import zombie.iso.IsoCell;

/** Shared PZ projectile/collision/damage service with no client HUD or ADS dependency. */
public final class PzBallisticService {
    private final BallisticEngine engine = new BallisticEngine();
    private final PzBallisticCoordinates coordinates;
    private final PzImpactDamageHandler damageHandler = new PzImpactDamageHandler();

    public PzBallisticService(PzBallisticCoordinates coordinates) {
        this.coordinates = Objects.requireNonNull(coordinates, "coordinates");
    }

    /**
     * Launches a server- or client-authoritative shot from already validated
     * world-space inputs. The attachment is opaque to the simulator and can
     * carry replication or local visual metadata.
     */
    public boolean launch(BallisticProfile profile, BallisticVector3 muzzle,
                          BallisticVector3 direction, IsoGameCharacter shooter,
                          HandWeapon weapon, PzImpactDamageHandler.DamagePlan damagePlan,
                          Object attachment) {
        if (profile == null || muzzle == null || direction == null || shooter == null
                || weapon == null || damagePlan == null) return false;
        double directionLengthSquared = direction.lengthSquared();
        if (!Double.isFinite(directionLengthSquared) || directionLengthSquared < 1.0e-12) {
            return false;
        }
        return engine.launch(profile, muzzle, direction, shooter,
                new ShotData(weapon, damagePlan, attachment));
    }

    /** Advances projectiles on the PZ main thread and applies PZ damage on impact. */
    public List<BallisticEngine.Impact> update(IsoCell cell, double frameSeconds) {
        if (cell == null || !Double.isFinite(frameSeconds) || frameSeconds <= 0.0) return List.of();
        List<BallisticEngine.Impact> impacts = engine.update(frameSeconds,
                new PzCollisionResolver(cell, coordinates, false));
        for (BallisticEngine.Impact impact : impacts) {
            if (!(impact.projectile().shotData() instanceof ShotData shot)) continue;
            if (impact.projectile().owner() instanceof IsoGameCharacter shooter) {
                damageHandler.apply(impact, shooter, shot.weapon, shot.damagePlan);
            }
        }
        return impacts;
    }

    public int activeCount() { return engine.activeCount(); }
    public List<BallisticProjectile> activeProjectilesSnapshot() {
        return engine.activeProjectilesSnapshot();
    }
    public void clear() { engine.clear(); }

    /** Returns the caller-owned metadata attached to a completed impact, if any. */
    public static Object attachment(BallisticEngine.Impact impact) {
        if (impact == null || !(impact.projectile().shotData() instanceof ShotData shot)) return null;
        return shot.attachment;
    }

    private record ShotData(HandWeapon weapon,
                            PzImpactDamageHandler.DamagePlan damagePlan,
                            Object attachment) {}
}

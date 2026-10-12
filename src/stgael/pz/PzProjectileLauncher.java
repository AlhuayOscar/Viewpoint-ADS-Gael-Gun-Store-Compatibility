package stgael.pz;

import java.lang.reflect.Method;
import java.util.Objects;

import stgael.ballistics.BallisticProfile;
import zombie.characters.IsoGameCharacter;
import zombie.core.physics.BallisticsController;
import zombie.inventory.types.HandWeapon;
import zombie.iso.Vector3;

/** Creates independent projectiles from PZ's muzzle and the current physical ADS barrel axis. */
public final class PzProjectileLauncher {
    private static volatile Method directionBridge;

    private final PzBallisticService service;
    private final PzBallisticCoordinates coordinates;

    public PzProjectileLauncher(PzBallisticService service, PzBallisticCoordinates coordinates) {
        this.service = Objects.requireNonNull(service, "service");
        this.coordinates = Objects.requireNonNull(coordinates, "coordinates");
    }

    /**
     * Returns false unless PZ supplied a valid muzzle and the ADS bridge provided
     * a fresh matching weapon pose. A caller must then leave native shot handling on.
     */
    public boolean launch(BallisticsController controller, HandWeapon weapon,
                          IsoGameCharacter shooter, BallisticProfile profile,
                          PzImpactDamageHandler.DamagePlan damagePlan, Object shotData) {
        if (controller == null || weapon == null || shooter == null || profile == null) return false;
        Vector3 muzzle = new Vector3();
        Vector3 nativeDirection = new Vector3();
        float range = controller.calculateMuzzlePosition(muzzle, nativeDirection);
        if (!Float.isFinite(range) || range <= 0.0f) return false;
        applyCalibratedMuzzle(controller, muzzle);

        Vector3 physicalDirection = new Vector3();
        if (!readPhysicalDirection(weapon.getFullType(), physicalDirection)) return false;
        var worldMuzzle = coordinates.positionToMetres(muzzle);
        var worldDirection = coordinates.directionToMetres(physicalDirection);
        return service.launch(profile, worldMuzzle, worldDirection, shooter, weapon,
                damagePlan, shotData);
    }

    private static boolean readPhysicalDirection(String weaponId, Vector3 output) {
        try {
            Method bridge = directionBridge;
            if (bridge == null) {
                Class<?> bridgeClass = Class.forName("pvads.GaelNativeShot");
                bridge = bridgeClass.getMethod("currentPhysicalShotDirection", String.class, Vector3.class);
                directionBridge = bridge;
            }
            return Boolean.TRUE.equals(bridge.invoke(null, weaponId, output));
        } catch (ReflectiveOperationException | LinkageError unavailable) {
            return false;
        }
    }

    private static void applyCalibratedMuzzle(BallisticsController controller, Vector3 muzzle) {
        try {
            Class<?> bridgeClass = Class.forName("pvads.GaelNativeShot");
            bridgeClass.getMethod("afterLean", Object.class, Object.class)
                    .invoke(null, controller, muzzle);
        } catch (ReflectiveOperationException | LinkageError unavailable) {
            // The native controller's own muzzle remains valid when no ADS offset is configured.
        }
    }
}

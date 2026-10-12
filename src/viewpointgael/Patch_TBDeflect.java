package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelWeaponMotion;

/** ADS already supplies the weapon's physical pitch/yaw, so True Ballistics must not add a second cone. */
@Patch(className = "vtb.projectile.ProjectilePhysics", methodName = "deflect", strictMatch = true)
public final class Patch_TBDeflect {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter() {
        return GaelWeaponMotion.ready();
    }

    private Patch_TBDeflect() {}
}

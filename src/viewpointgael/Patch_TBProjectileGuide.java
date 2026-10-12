package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelNativeShot;

/** Applies the short, first-shot aim-assist curve before each simulation step. */
@Patch(className = "vtb.projectile.BallisticsManager", methodName = "simulate", strictMatch = true)
public final class Patch_TBProjectileGuide {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) Object projectile,
                             @Patch.Argument(1) double frameSeconds) {
        GaelNativeShot.guideTrueBallisticsProjectile(projectile, frameSeconds);
    }

    private Patch_TBProjectileGuide() {}
}

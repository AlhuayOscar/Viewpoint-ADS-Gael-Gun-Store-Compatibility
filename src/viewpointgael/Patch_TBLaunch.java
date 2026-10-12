package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelNativeShot;

/** Reorient the live projectiles after True Ballistics has solved and spawned this shot. */
@Patch(className = "vtb.projectile.BallisticsManager", methodName = "launch", strictMatch = true)
public final class Patch_TBLaunch {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.This Object manager, @Patch.Argument(3) Object group) {
        GaelNativeShot.correctTrueBallisticsShot(manager, group);
    }

    private Patch_TBLaunch() {}
}
